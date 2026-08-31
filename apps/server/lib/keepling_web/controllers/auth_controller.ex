defmodule KeeplingWeb.AuthController do
  use KeeplingWeb, :controller

  alias Keepling.Accounts

  def setup(conn, params) do
    with {:ok, setup} <- decode_setup(params),
         {:ok, result} <-
           Accounts.consume_setup(
             Map.put(setup, :accepted_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
           ) do
      conn
      |> put_status(201)
      |> json(%{status: "setup_complete", timezone: result.timezone})
    else
      {:error, :invalid_timezone} ->
        problem(conn, "invalid_timezone", "Choose a valid IANA timezone.", "correct_timezone")

      {:error, :invalid_password} ->
        problem(conn, "invalid_setup", "Check the setup form and try again.", "correct_setup")

      {:error, :setup_unavailable} ->
        problem(conn, "setup_unavailable", "Request a new setup link.", "request_setup_link")

      {:error, :invalid_setup} ->
        problem(conn, "invalid_setup", "Check the setup form and try again.", "correct_setup")

      {:error, :infrastructure_failure} ->
        conn
        |> put_status(503)
        |> put_resp_content_type("application/problem+json")
        |> json(%{
          code: "service_unavailable",
          recovery_action: "retry_setup",
          retryable: true,
          status: 503,
          title: "Keepling is temporarily unavailable",
          type: "/problems/service_unavailable"
        })
    end
  end

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

  defp problem(conn, code, detail, recovery_action) do
    conn
    |> put_status(422)
    |> put_resp_content_type("application/problem+json")
    |> json(%{
      code: code,
      detail: detail,
      recovery_action: recovery_action,
      retryable: false,
      status: 422,
      title: "Setup could not be completed",
      type: "/problems/#{code}"
    })
  end
end
