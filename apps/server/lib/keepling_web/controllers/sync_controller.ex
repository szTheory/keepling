defmodule KeeplingWeb.SyncController do
  use KeeplingWeb, :controller

  alias Keepling.Adapters.Postgres.SyncFeed
  alias Keepling.Application.Sync

  @pull_default 200
  @pull_maximum 200
  @bootstrap_default 50
  @bootstrap_maximum 100

  def pull(conn, params), do: run(conn, params, :pull)
  def bootstrap(conn, params), do: run(conn, params, :bootstrap)

  defp run(%{assigns: %{device_grant_namespace: grant_namespace}} = conn, params, action) do
    maximum = if action == :pull, do: @pull_maximum, else: @bootstrap_maximum
    default = if action == :pull, do: @pull_default, else: @bootstrap_default

    with {:ok, options} <- options(params, default, maximum),
         {:ok, context} <- synchronization_context(conn, grant_namespace),
         result <- invoke(action, context, options) do
      render_result(conn, result)
    else
      {:error, :invalid_query} -> invalid_query(conn)
      {:error, reason} -> render_result(conn, {:error, reason})
    end
  end

  defp options(params, default, maximum) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ["cursor", "limit"])),
         {:ok, limit} <- parse_limit(Map.get(params, "limit"), default, maximum) do
      {:ok, %{cursor: Map.get(params, "cursor"), limit: limit}}
    else
      _invalid -> {:error, :invalid_query}
    end
  end

  defp parse_limit(nil, default, _maximum), do: {:ok, default}

  defp parse_limit(value, _default, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit >= 1 and limit <= maximum -> {:ok, limit}
      _invalid -> {:error, :invalid_query}
    end
  end

  defp parse_limit(_value, _default, _maximum), do: {:error, :invalid_query}

  defp synchronization_context(conn, grant_namespace) do
    policy = Application.fetch_env!(:keepling, :compatibility)
    protocol_train = Map.fetch!(policy, "current_protocol_train")

    with {:ok, context} <- SyncFeed.synchronization_context(grant_namespace, protocol_train) do
      {:ok,
       context
       |> Map.put(:cursor_keyring, cursor_keyring(conn))
       |> Map.put(:now, DateTime.utc_now())}
    end
  end

  defp cursor_keyring(conn) do
    secret =
      :crypto.mac(
        :hmac,
        :sha256,
        conn.private.phoenix_endpoint.config(:secret_key_base),
        "keepling-sync-cursor-v1"
      )

    %{active: "v1", keys: %{"v1" => secret}}
  end

  defp invoke(:pull, context, options), do: Sync.pull(context, options, SyncFeed)
  defp invoke(:bootstrap, context, options), do: Sync.bootstrap(context, options, SyncFeed)

  defp render_result(conn, {:ok, body}), do: json(conn, body)

  defp render_result(conn, {:quarantined, :namespace_mismatch}),
    do: reset_problem(conn, "namespace_mismatch", "quarantine")

  defp render_result(conn, {:reset_required, %{reason: reason, recovery: recovery}}),
    do: reset_problem(conn, reason, recovery)

  defp render_result(conn, {:error, :invalid_limit}), do: invalid_query(conn)

  defp render_result(conn, {:error, :sync_epoch_unavailable}),
    do: problem(conn, 503, "sync_unavailable", "Synchronization unavailable", true, "retry")

  defp render_result(conn, {:error, _reason}),
    do: problem(conn, 503, "sync_unavailable", "Synchronization unavailable", true, "retry")

  defp invalid_query(conn),
    do:
      problem(
        conn,
        400,
        "invalid_sync_query",
        "Invalid synchronization query",
        false,
        "correct_request"
      )

  defp reset_problem(conn, reason, recovery) do
    code =
      case reason do
        "tampered_cursor" -> "sync_cursor_tampered"
        "namespace_mismatch" -> "sync_namespace_mismatch"
        "unsupported_protocol" -> "sync_protocol_unsupported"
        "unsupported_codec" -> "sync_codec_unsupported"
        "restore_epoch_changed" -> "sync_restore_epoch_changed"
        "cursor_expired" -> "sync_cursor_expired"
        "below_low_water" -> "sync_cursor_below_low_water"
      end

    problem(conn, 409, code, "Synchronization reset required", false, recovery)
  end

  defp problem(conn, status, code, title, retryable, recovery_action) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> put_status(status)
    |> json(%{
      code: code,
      recovery_action: recovery_action,
      retryable: retryable,
      status: status,
      title: title,
      type: "/problems/#{code}"
    })
  end
end
