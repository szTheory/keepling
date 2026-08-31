defmodule KeeplingWeb.Auth do
  @moduledoc false

  import Plug.Conn

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @session_key :session_credential

  def init(action), do: action

  def call(conn, :load_session), do: load_session(conn)
  def call(conn, :require_authenticated), do: require_authenticated(conn)
  def call(conn, :require_trusted_origin), do: require_trusted_origin(conn)
  def call(conn, :require_test_fixture), do: require_test_fixture(conn)

  def sign_in_test_account(conn) do
    with %{rows: [[account_id]]} <-
           SQL.query!(Repo, "SELECT id FROM accounts WHERE singleton_key = TRUE", []),
         credential <- random_credential(),
         credential_hash <- hash(credential),
         session_id <- Ecto.UUID.generate(),
         now <- DateTime.utc_now(),
         expires_at <- DateTime.add(now, 3_600, :second),
         {:ok, _result} <-
           SQL.query(
             Repo,
             """
             INSERT INTO sessions (
               id, account_id, credential_hash, created_at, expires_at, inserted_at, updated_at
             )
             VALUES ($1, $2, $3, $4, $5, $4, $4)
             """,
             [Ecto.UUID.dump!(session_id), account_id, credential_hash, now, expires_at]
           ) do
      Plug.CSRFProtection.delete_csrf_token()

      signed_in_conn =
        conn
        |> configure_session(renew: true)
        |> put_session(@session_key, credential)
        |> assign(:current_account_id, account_id)

      {:ok, signed_in_conn, Plug.CSRFProtection.get_csrf_token()}
    else
      _ -> {:error, :fixture_unavailable}
    end
  end

  defp load_session(conn) do
    with credential when is_binary(credential) <- get_session(conn, @session_key),
         credential_hash <- hash(credential),
         %{rows: [[account_id]]} <-
           SQL.query!(
             Repo,
             """
             SELECT account_id
             FROM sessions
             WHERE credential_hash = $1 AND revoked_at IS NULL AND expires_at > NOW()
             """,
             [credential_hash]
           ) do
      assign(conn, :current_account_id, account_id)
    else
      _ -> conn
    end
  end

  defp require_authenticated(%{assigns: %{current_account_id: _account_id}} = conn), do: conn

  defp require_authenticated(conn) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(
      401,
      Jason.encode!(%{
        code: "authentication_required",
        recovery_action: "sign_in",
        retryable: false,
        status: 401,
        title: "Authentication required",
        type: "/problems/authentication_required"
      })
    )
    |> halt()
  end

  defp require_trusted_origin(conn) do
    expected = "#{conn.scheme}://#{List.first(get_req_header(conn, "host"))}"

    case get_req_header(conn, "origin") do
      [^expected] -> conn
      _ -> forbidden(conn)
    end
  end

  defp require_test_fixture(conn) do
    if Mix.env() == :test and System.get_env("KEEPLING_E2E_SEED") == "phase-1" do
      conn
      |> require_trusted_origin()
      |> put_private(:plug_skip_csrf_protection, true)
    else
      conn |> send_resp(404, "") |> halt()
    end
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(
      403,
      Jason.encode!(%{
        code: "origin_not_allowed",
        recovery_action: "reload_same_origin",
        retryable: false,
        status: 403,
        title: "Origin not allowed",
        type: "/problems/origin_not_allowed"
      })
    )
    |> halt()
  end

  defp random_credential do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp hash(value), do: :crypto.hash(:sha256, value)
end
