if Mix.env() == :test do
  defmodule KeeplingWeb.TestFaultController do
    @moduledoc false

    @behaviour Plug

    import Plug.Conn

    defmodule ConnectionDropped do
      defexception message: "test connection dropped"
    end

    @impl Plug
    def init(options), do: options

    @impl Plug
    def call(conn, _options) do
      case get_req_header(conn, "x-keepling-test-fault") do
        [] ->
          conn

        [mode]
        when mode in [
               "before_acceptance",
               "after_commit",
               "authentication_before_acceptance",
               "authentication_after_commit"
             ] ->
          authorize_fault(conn, mode)

        _closed_value ->
          not_found(conn)
      end
    end

    defp authorize_fault(conn, mode) do
      provided = List.first(get_req_header(conn, "x-keepling-test-fault-token"))
      expected = System.get_env("KEEPLING_TEST_FAULT_TOKEN")

      if credential_matches?(provided, expected) do
        apply_fault(conn, mode)
      else
        not_found(conn)
      end
    end

    defp credential_matches?(provided, expected)
         when is_binary(provided) and is_binary(expected) and
                byte_size(provided) == byte_size(expected) and
                byte_size(expected) >= 32 do
      Plug.Crypto.secure_compare(provided, expected)
    end

    defp credential_matches?(_provided, _expected), do: false

    defp apply_fault(conn, "before_acceptance") do
      conn
      |> put_resp_content_type("application/problem+json")
      |> send_resp(
        503,
        ~s({"type":"about:blank","title":"Test transport unavailable","status":503,"code":"test_transport_unavailable","retryable":true,"recovery_action":"check_mutation"})
      )
      |> halt()
    end

    defp apply_fault(conn, "after_commit") do
      register_before_send(conn, fn _conn -> raise ConnectionDropped end)
    end

    defp apply_fault(conn, "authentication_before_acceptance") do
      conn
      |> authentication_required()
      |> halt()
    end

    defp apply_fault(conn, "authentication_after_commit") do
      register_before_send(conn, &authentication_required/1)
    end

    defp authentication_required(conn) do
      conn
      |> delete_resp_header("content-length")
      |> put_resp_content_type("application/problem+json")
      |> resp(
        401,
        ~s({"type":"about:blank","title":"Authentication required","status":401,"code":"authentication_required","retryable":true,"recovery_action":"reauthenticate"})
      )
    end

    defp not_found(conn) do
      conn
      |> send_resp(404, "not found")
      |> halt()
    end
  end
end
