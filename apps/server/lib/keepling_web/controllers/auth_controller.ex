defmodule KeeplingWeb.AuthController do
  use KeeplingWeb, :controller

  alias Keepling.Accounts
  alias Keepling.Accounts.RateLimit
  alias KeeplingWeb.Auth

  def setup(conn, params) do
    with :ok <- RateLimit.admit(:setup, conn.remote_ip),
         {:ok, setup} <- decode_setup(params),
         {:ok, result} <-
           Accounts.consume_setup(
             Map.put(setup, :accepted_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
           ) do
      RateLimit.emit_decision(:setup, :accepted)

      conn
      |> put_status(201)
      |> json(%{status: "setup_complete", timezone: result.timezone})
    else
      {:error, :rate_limited, _retry_after_ms} ->
        invalid_setup(conn)

      {:error, :invalid_timezone} ->
        RateLimit.emit_decision(:setup, :invalid)

        problem(
          conn,
          422,
          "invalid_timezone",
          "Choose a valid IANA timezone.",
          "correct_timezone"
        )

      {:error, reason} when reason in [:invalid_password, :invalid_setup] ->
        RateLimit.emit_decision(:setup, :invalid)
        invalid_setup(conn)

      {:error, :setup_unavailable} ->
        RateLimit.emit_decision(:setup, :invalid)
        problem(conn, 422, "setup_unavailable", "Request a new setup link.", "request_setup_link")

      {:error, :infrastructure_failure} ->
        infrastructure_problem(conn, "retry_setup")
    end
  end

  def login(conn, params) do
    with :ok <- RateLimit.admit(:login, conn.remote_ip),
         {:ok, request} <- decode_login(params),
         {:ok, session} <-
           Accounts.login(request.password,
             label: request.label,
             client_kind: request.client_kind
           ) do
      RateLimit.emit_decision(:login, :accepted)
      authenticated(conn, session, "authenticated")
    else
      {:error, :rate_limited, _retry_after_ms} ->
        authentication_failed(conn)

      {:error, :invalid_request} ->
        RateLimit.emit_decision(:login, :invalid)
        authentication_failed(conn)

      {:error, :authentication_failed} ->
        RateLimit.emit_decision(:login, :invalid)
        authentication_failed(conn)

      {:error, :infrastructure_failure} ->
        infrastructure_problem(conn, "retry_login")
    end
  end

  def recovery(conn, params) do
    with :ok <- RateLimit.admit(:recovery, conn.remote_ip),
         {:ok, request} <- decode_recovery(params),
         {:ok, session} <-
           Accounts.consume_recovery(%{
             accepted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
             client_kind: request.client_kind,
             label: request.label,
             password: request.password,
             token: request.token
           }) do
      RateLimit.emit_decision(:recovery, :accepted)
      authenticated(conn, session, "recovery_complete")
    else
      {:error, :rate_limited, _retry_after_ms} ->
        recovery_unavailable(conn)

      {:error, :invalid_request} ->
        RateLimit.emit_decision(:recovery, :invalid)
        recovery_unavailable(conn)

      {:error, reason}
      when reason in [
             :invalid_password,
             :invalid_label,
             :invalid_client_kind,
             :recovery_unavailable
           ] ->
        RateLimit.emit_decision(:recovery, :invalid)
        recovery_unavailable(conn)

      {:error, :infrastructure_failure} ->
        infrastructure_problem(conn, "retry_recovery")
    end
  end

  def reauthenticate(conn, params) do
    with :ok <-
           RateLimit.admit(
             :reauthentication,
             conn.assigns.current_account_id,
             conn.remote_ip,
             []
           ),
         {:ok, password} <- decode_reauthentication(params),
         :ok <- Accounts.reauthenticate(conn.assigns.current_account_id, password),
         {:ok, session} <-
           Accounts.rotate_session(
             conn.assigns.current_account_id,
             conn.assigns.current_session_id
           ) do
      RateLimit.emit_decision(:reauthentication, :accepted)
      authenticated(conn, session, "recently_authenticated")
    else
      {:error, :rate_limited, _retry_after_ms} ->
        authentication_failed(conn)

      {:error, reason}
      when reason in [:invalid_request, :authentication_failed, :session_unavailable] ->
        RateLimit.emit_decision(:reauthentication, :invalid)
        authentication_failed(conn)

      {:error, :infrastructure_failure} ->
        infrastructure_problem(conn, "retry_reauthentication")
    end
  end

  def logout(conn, %{"version" => 1} = params) when map_size(params) == 1 do
    case Accounts.logout(conn.assigns.current_account_id, conn.assigns.current_session_id) do
      :ok -> conn |> Auth.clear_session() |> json(%{status: "signed_out"})
      {:error, :infrastructure_failure} -> infrastructure_problem(conn, "retry_logout")
    end
  end

  def logout(conn, _params), do: invalid_request(conn)

  def sessions(conn, _params) do
    case Accounts.list_sessions(
           conn.assigns.current_account_id,
           conn.assigns.current_session_id
         ) do
      {:ok, sessions} -> json(conn, %{sessions: sessions})
      {:error, :infrastructure_failure} -> infrastructure_problem(conn, "retry_sessions")
    end
  end

  def update_session(conn, %{"id" => session_id} = params) do
    case decode_session_label(Map.delete(params, "id")) do
      {:ok, label} ->
        case Accounts.rename_session(conn.assigns.current_account_id, session_id, label) do
          {:ok, result} ->
            json(conn, result)

          {:error, :invalid_label} ->
            invalid_request(conn)

          {:error, :session_unavailable} ->
            session_unavailable(conn)

          {:error, :infrastructure_failure} ->
            infrastructure_problem(conn, "retry_session_update")
        end

      {:error, :invalid_request} ->
        invalid_request(conn)
    end
  end

  def revoke_session(conn, %{"id" => session_id}) do
    case Accounts.revoke_session(conn.assigns.current_account_id, session_id) do
      {:ok, result} ->
        if session_id == Ecto.UUID.load!(conn.assigns.current_session_id) do
          conn |> Auth.clear_session() |> json(result)
        else
          json(conn, result)
        end

      {:error, :session_unavailable} ->
        session_unavailable(conn)

      {:error, :infrastructure_failure} ->
        infrastructure_problem(conn, "retry_session_revocation")
    end
  end

  defp authenticated(conn, session, status) do
    signed_in_conn =
      conn
      |> Auth.establish_session(session)
      |> maybe_initialize_csrf(status)

    json(signed_in_conn, %{
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      status: status
    })
  end

  defp maybe_initialize_csrf(conn, "recently_authenticated"), do: conn
  defp maybe_initialize_csrf(conn, _status), do: Auth.initialize_csrf(conn)

  defp decode_setup(params) do
    allowed_keys = ["password", "timezone", "token", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "password" => password,
           "timezone" => timezone,
           "token" => token,
           "version" => 1
         }
         when is_binary(password) and is_binary(timezone) and is_binary(token) <- params do
      {:ok, %{password: password, timezone: timezone, token: token}}
    else
      _ -> {:error, :invalid_setup}
    end
  end

  defp decode_login(params) do
    allowed_keys = ["client_kind", "label", "password", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "client_kind" => client_kind,
           "label" => label,
           "password" => password,
           "version" => 1
         }
         when is_binary(client_kind) and is_binary(label) and is_binary(password) <- params do
      {:ok, %{client_kind: client_kind, label: label, password: password}}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp decode_recovery(params) do
    allowed_keys = ["client_kind", "label", "password", "token", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "client_kind" => client_kind,
           "label" => label,
           "password" => password,
           "token" => token,
           "version" => 1
         }
         when is_binary(client_kind) and is_binary(label) and is_binary(password) and
                is_binary(token) <- params do
      {:ok, %{client_kind: client_kind, label: label, password: password, token: token}}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp decode_reauthentication(%{"password" => password, "version" => 1} = params)
       when map_size(params) == 2 and is_binary(password),
       do: {:ok, password}

  defp decode_reauthentication(_params), do: {:error, :invalid_request}

  defp decode_session_label(%{"label" => label, "version" => 1} = params)
       when map_size(params) == 2 and is_binary(label),
       do: {:ok, label}

  defp decode_session_label(_params), do: {:error, :invalid_request}

  defp invalid_request(conn) do
    problem(
      conn,
      400,
      "invalid_request",
      "Send the closed version 1 authentication request.",
      "correct_request"
    )
  end

  defp invalid_setup(conn) do
    problem(
      conn,
      422,
      "invalid_setup",
      "Check the setup form and try again.",
      "correct_setup"
    )
  end

  defp authentication_failed(conn) do
    problem(conn, 401, "authentication_failed", nil, "check_credentials", "Authentication failed")
  end

  defp recovery_unavailable(conn) do
    problem(
      conn,
      422,
      "recovery_unavailable",
      "Request a new recovery link.",
      "request_recovery_link",
      "Recovery could not be completed"
    )
  end

  defp session_unavailable(conn) do
    problem(
      conn,
      404,
      "session_unavailable",
      nil,
      "refresh_sessions",
      "Session not available"
    )
  end

  defp infrastructure_problem(conn, recovery_action) do
    conn
    |> put_status(503)
    |> put_resp_content_type("application/problem+json")
    |> json(%{
      code: "service_unavailable",
      recovery_action: recovery_action,
      retryable: true,
      status: 503,
      title: "Keepling is temporarily unavailable",
      type: "/problems/service_unavailable"
    })
  end

  defp problem(
         conn,
         status,
         code,
         detail,
         recovery_action,
         title \\ "Request could not be completed"
       ) do
    body = %{
      code: code,
      recovery_action: recovery_action,
      retryable: false,
      status: status,
      title: title,
      type: "/problems/#{code}"
    }

    body = if detail, do: Map.put(body, :detail, detail), else: body

    conn
    |> put_status(status)
    |> put_resp_content_type("application/problem+json")
    |> json(body)
  end
end
