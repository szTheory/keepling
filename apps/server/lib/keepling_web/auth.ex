defmodule KeeplingWeb.Auth do
  @moduledoc false

  import Plug.Conn

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Repo

  @session_key :session_credential

  def init(action), do: action

  def call(conn, :load_session), do: load_session(conn)
  def call(conn, :require_authenticated), do: require_authenticated(conn)
  def call(conn, :require_recent_auth), do: require_recent_auth(conn)
  def call(conn, :require_trusted_origin), do: require_trusted_origin(conn)
  def call(conn, :require_test_fixture), do: require_test_fixture(conn)

  def establish_session(conn, session) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, session.credential)
    |> assign_session(session)
  end

  def initialize_csrf(conn) do
    conn
    |> put_private(:plug_skip_csrf_protection, true)
    |> Plug.CSRFProtection.call(Plug.CSRFProtection.init([]))
  end

  def clear_session(conn) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> delete_session(@session_key)
    |> configure_session(drop: true)
  end

  def sign_in_test_account(conn) do
    with %{rows: [[account_id]]} <-
           SQL.query!(Repo, "SELECT id FROM accounts WHERE singleton_key = TRUE", []),
         {:ok, session} <-
           Accounts.create_session(account_id,
             label: "Test browser",
             client_kind: "web"
           ) do
      signed_in_conn = establish_session(conn, session)
      {:ok, signed_in_conn, Plug.CSRFProtection.get_csrf_token()}
    else
      _ -> {:error, :fixture_unavailable}
    end
  end

  defp load_session(conn) do
    with credential when is_binary(credential) <- get_session(conn, @session_key),
         {:ok, session} <- Accounts.authenticate_session(credential) do
      assign_session(conn, session)
    else
      _ -> conn
    end
  end

  defp assign_session(conn, session) do
    conn
    |> assign(:current_account_id, session.account_id)
    |> assign(:current_session_id, session.session_id)
    |> assign(:recently_authenticated?, Map.get(session, :recently_authenticated?, true))
  end

  defp require_authenticated(%{assigns: %{current_account_id: _account_id}} = conn), do: conn

  defp require_authenticated(conn) do
    conn
    |> authentication_problem(
      "authentication_required",
      "Authentication required",
      "sign_in"
    )
    |> halt()
  end

  defp require_recent_auth(%{assigns: %{recently_authenticated?: true}} = conn), do: conn

  defp require_recent_auth(conn) do
    conn
    |> authentication_problem(
      "recent_authentication_required",
      "Recent authentication required",
      "reauthenticate"
    )
    |> halt()
  end

  defp authentication_problem(conn, code, title, recovery_action) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(
      401,
      Jason.encode!(%{
        code: code,
        recovery_action: recovery_action,
        retryable: false,
        status: 401,
        title: title,
        type: "/problems/#{code}"
      })
    )
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
end
