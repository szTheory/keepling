defmodule Keepling.Application.Preview do
  @moduledoc """
  MCP-05: two-step preview/commit for bulk and destructive agent changes
  (D-17, D-18, D-19, D-34).

  `mint/3` returns an opaque, account-bound, expiring token that binds the
  exact target identity set, each target's expected revision, the command
  and its arguments, the server instance, and the synchronization epoch --
  mirroring the signed cursor construction in
  `Keepling.Application.TaskViews.encode_cursor/3`. `commit/4` accepts only
  that token and a mutation identity -- never a re-sent target list -- and
  delegates to the configured `Port` for the single-transaction, atomic
  re-verification and application (D-18: any drift fails the WHOLE commit
  as `:preview_stale` with zero partial writes; there is no per-target
  success shape).

  `authorize_commit/2` is the pure, directly-testable comparison the
  adapter's transaction calls after re-reading live target state -- the
  direct analog of `Keepling.Adapters.Postgres.SyncFeed.authorize_namespace/2`.
  """

  @destructive_commands ~w(trash_task restore_task undo_task)a
  @binding_fields [:account_id, :arguments, :command, :server_instance, :sync_epoch, :targets]
  @maximum_targets 25
  @token_ttl_seconds 15 * 60
  @mac_bytes 32

  defmodule Port do
    @moduledoc """
    Persistence port for preview commit. `lock_targets/3` locks every
    target row `FOR UPDATE` in deterministic identity order and returns
    live revisions. `apply_all/4` runs the single transaction: replay
    detection, `lock_targets/3`, the `authorize` callback (always
    `&Preview.authorize_commit/2` in production), and -- only if
    authorized -- application of every target's command through
    `Keepling.Application.Commands.dispatch/3` /
    `Keepling.Application.Undo.dispatch/3`, exactly as a human client
    would. `current_sync_epoch/1` is a read-only peek used both at mint
    time (to bind the epoch) and at commit time (to re-verify it).
    """

    @callback current_sync_epoch(map()) :: {:ok, String.t()} | {:error, atom()}
    @callback lock_targets(map(), map(), [map()]) :: {:ok, [map()]} | {:error, atom()}
    @callback apply_all(map(), String.t(), map(), function()) :: {:ok, map()} | {:error, atom()}
  end

  @doc "The closed D-19 destructive vocabulary, plus any command whose target set has more than one member."
  @spec destructive?(map()) :: boolean()
  def destructive?(%{command: command, targets: targets})
      when is_atom(command) and is_list(targets),
      do: command in @destructive_commands or length(targets) > 1

  def destructive?(_params), do: false

  @doc "Mints an opaque, account-bound, expiring preview token binding the closed field list."
  @spec mint(map(), map(), module()) :: {:ok, map()} | {:error, :invalid_preview}
  def mint(%{command: command, targets: targets} = params, context, port)
      when is_atom(command) and is_list(targets) and is_map(context) do
    arguments = Map.get(params, :arguments, %{})

    with true <- targets != [] and length(targets) <= @maximum_targets,
         true <- Enum.all?(targets, &valid_target?/1),
         true <- unique_target_ids?(targets),
         {:ok, sync_epoch} <- port.current_sync_epoch(context) do
      now = Map.fetch!(context, :accepted_at)
      expires_at = DateTime.add(now, @token_ttl_seconds, :second)

      binding = %{
        account_id: Map.fetch!(context, :account_id),
        arguments: arguments,
        command: Atom.to_string(command),
        expires_at: expires_at,
        server_instance: server_instance(),
        sync_epoch: sync_epoch,
        targets: normalize_targets(targets)
      }

      {:ok,
       %{
         token: encode_token(binding, context),
         expires_at: expires_at,
         summary: summarize(command, targets)
       }}
    else
      _ -> {:error, :invalid_preview}
    end
  end

  def mint(_params, _context, _port), do: {:error, :invalid_preview}

  @doc """
  Decodes and expiry-checks the token, then delegates to `port.apply_all/4`
  with `&authorize_commit/2` as the authorization callback the adapter's
  single transaction invokes after re-reading live target state. Commit
  takes only the token and a mutation identity -- never a target list.
  """
  @spec commit(String.t(), String.t(), map(), module()) ::
          {:ok, map()} | {:error, :preview_invalid | :preview_expired | atom()}
  def commit(token, mutation_id, context, port)
      when is_binary(token) and is_binary(mutation_id) and is_map(context) do
    with {:ok, binding} <- decode_token(token, context),
         :ok <- check_not_expired(binding, context) do
      port.apply_all(binding, mutation_id, context, &authorize_commit/2)
    end
  end

  def commit(_token, _mutation_id, _context, _port), do: {:error, :preview_invalid}

  @doc """
  Direct analog of `SyncFeed.authorize_namespace/2`: exact `Map.take`
  equality over the closed `@binding_fields` list, with `Enum.has_key?`
  presence assertions on both sides so an omitted field cannot compare
  equal via two absences. A mismatch or missing field anywhere EXCEPT
  `:targets` is `:preview_invalid` (wrong account, wrong server instance,
  wrong sync epoch, tampered command/arguments); a `:targets` mismatch
  alone is `:preview_stale` (D-18 -- a target changed, disappeared, or the
  set no longer matches).
  """
  @spec authorize_commit(map(), map()) :: :ok | {:error, :preview_invalid | :preview_stale}
  def authorize_commit(supplied, authoritative) when is_map(supplied) and is_map(authoritative) do
    present? =
      Enum.all?(@binding_fields, &Map.has_key?(supplied, &1)) and
        Enum.all?(@binding_fields, &Map.has_key?(authoritative, &1))

    context_fields = @binding_fields -- [:targets]

    cond do
      not present? ->
        {:error, :preview_invalid}

      Map.take(supplied, context_fields) != Map.take(authoritative, context_fields) ->
        {:error, :preview_invalid}

      Map.get(supplied, :targets) != Map.get(authoritative, :targets) ->
        {:error, :preview_stale}

      true ->
        :ok
    end
  end

  def authorize_commit(_supplied, _authoritative), do: {:error, :preview_invalid}

  @doc "Static, boot-time-configured server instance identity (same value `device_grants` namespaces bind to)."
  @spec server_instance() :: String.t()
  def server_instance,
    do: Application.get_env(:keepling, :device_grants, []) |> Keyword.get(:server_instance, "")

  @doc "The closed maximum bound on a single preview's target set."
  @spec maximum_targets() :: pos_integer()
  def maximum_targets, do: @maximum_targets

  @doc "Preview token time-to-live, in seconds."
  @spec token_ttl_seconds() :: pos_integer()
  def token_ttl_seconds, do: @token_ttl_seconds

  @doc "The closed D-19 destructive command vocabulary."
  @spec destructive_commands() :: [atom()]
  def destructive_commands, do: @destructive_commands

  defp check_not_expired(%{expires_at: %DateTime{} = expires_at}, %{
         accepted_at: %DateTime{} = now
       }) do
    if DateTime.compare(expires_at, now) == :gt, do: :ok, else: {:error, :preview_expired}
  end

  defp check_not_expired(_binding, _context), do: {:error, :preview_invalid}

  # Format-only shape check (application layer has no outward adapter
  # dependency, per architecture_test.exs -- no Ecto.UUID here). The MCP
  # tool's own decode already casts each target_id through Ecto.UUID
  # before this module ever sees it (T-05-01 discipline: adapters
  # validate/cast, application trusts structurally-typed input).
  @uuid_shape ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  defp valid_target?(%{task_id: task_id, expected_revision: revision})
       when is_binary(task_id) and is_integer(revision) and revision >= 1 do
    Regex.match?(@uuid_shape, task_id)
  end

  defp valid_target?(_target), do: false

  defp unique_target_ids?(targets) do
    ids = Enum.map(targets, & &1.task_id)
    length(ids) == MapSet.size(MapSet.new(ids))
  end

  defp normalize_targets(targets) do
    targets
    |> Enum.map(&%{task_id: &1.task_id, expected_revision: &1.expected_revision})
    |> Enum.sort_by(& &1.task_id)
  end

  defp summarize(command, targets) do
    "#{Atom.to_string(command)} on #{length(targets)} task(s): " <>
      (targets |> Enum.map(& &1.task_id) |> Enum.sort() |> Enum.join(", "))
  end

  # Mirrors TaskViews.encode_cursor/3's construction exactly:
  # :erlang.term_to_binary/2 with [:deterministic], HMAC-SHA256, url-safe
  # base64 without padding. The HMAC key comes from `context.preview_secret`
  # -- an adapter-derived value (the caller computes it from
  # KeeplingWeb.Endpoint's secret_key_base, exactly as
  # TaskViewController/ActivityController derive `cursor_secret`) so this
  # application-layer module has no outward KeeplingWeb dependency
  # (architecture_test.exs).
  defp encode_token(binding, context) do
    payload = :erlang.term_to_binary(binding, [:deterministic])
    mac = :crypto.mac(:hmac, :sha256, Map.fetch!(context, :preview_secret), payload)
    Base.url_encode64(payload <> mac, padding: false)
  end

  # Mirrors TaskViews.decode_cursor/3's discipline: url-safe base64 decode,
  # constant-time MAC comparison, [:safe] term decoding (never the unsafe
  # single-argument form), then an account re-check on the decoded binding.
  defp decode_token(token, context)
       when is_binary(token) and byte_size(token) <= 8192 do
    with {:ok, signed} <- Base.url_decode64(token, padding: false),
         true <- byte_size(signed) > @mac_bytes,
         payload_size = byte_size(signed) - @mac_bytes,
         <<payload::binary-size(^payload_size), supplied_mac::binary-size(@mac_bytes)>> <- signed,
         expected_mac = :crypto.mac(:hmac, :sha256, Map.fetch!(context, :preview_secret), payload),
         true <- :crypto.hash_equals(supplied_mac, expected_mac),
         %{account_id: account_id} = binding <- :erlang.binary_to_term(payload, [:safe]),
         true <- account_id == Map.get(context, :account_id) do
      {:ok, binding}
    else
      _ -> {:error, :preview_invalid}
    end
  rescue
    _error -> {:error, :preview_invalid}
  end

  defp decode_token(_token, _context), do: {:error, :preview_invalid}
end
