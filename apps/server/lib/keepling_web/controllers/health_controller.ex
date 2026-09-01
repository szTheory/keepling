defmodule KeeplingWeb.HealthController do
  @moduledoc """
  Thin HTTP projection for process liveness, serving readiness, and operator status.

  Public probes expose only a closed state/code pair. Full bounded facts and
  remediation are available only after separate operator authentication.
  """

  use KeeplingWeb, :controller

  alias Keepling.Adapters.Postgres.OpsStore
  alias Keepling.Application.Ops

  @readiness_timeout_ms 250

  plug :require_operator when action in [:status]

  def live(conn, _params), do: json(conn, Ops.liveness())

  def ready(conn, _params) do
    result = Ops.readiness(ops_port(), %{timeout_ms: @readiness_timeout_ms})

    conn
    |> put_status(if(result["status"] == "ready", do: 200, else: 503))
    |> json(result)
  end

  def status(conn, _params) do
    result = Ops.run("status", %{}, ops_port(), %{timeout_ms: @readiness_timeout_ms})

    conn
    |> put_status(operator_status(result))
    |> json(result)
  end

  defp require_operator(conn, _options) do
    expected_hash = Application.get_env(:keepling, :operator_status_token_hash)

    authorized? =
      with hash when is_binary(hash) and byte_size(hash) == 32 <- expected_hash,
           ["Bearer " <> token] <- get_req_header(conn, "authorization"),
           true <- byte_size(token) >= 32,
           supplied_hash <- :crypto.hash(:sha256, token),
           true <- Plug.Crypto.secure_compare(supplied_hash, hash) do
        true
      else
        _ -> false
      end

    if authorized? do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        "code" => "operator_authentication_required",
        "status" => "unauthorized"
      })
      |> halt()
    end
  end

  defp operator_status(%{"status" => status}) when status in ["ok", "degraded"], do: 200
  defp operator_status(_result), do: 503

  defp ops_port do
    Application.get_env(:keepling, :ops_port, OpsStore)
  end
end
