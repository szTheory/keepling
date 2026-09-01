defmodule Keepling.Application.Ops.Restore do
  @moduledoc """
  Closed inward restore state machine.

  Restore sources and targets are untrusted until admitted here. The outward
  port owns persistence, but must make target lease acquisition exclusive and
  epoch/proof finalization transactional. Records retain only immutable
  digests, closed compatibility facts, timestamps, and outcome codes.
  """

  @digest ~r/^sha256:[0-9a-f]{64}$/
  @uuid_v4 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  @semantic ~w(history login read schema undo write)

  defmodule Port do
    @moduledoc "Persistence boundary for exclusive restore runs and completed proof."

    @callback lookup_completed(term(), term()) :: {:ok, map()} | :error | {:error, atom()}
    @callback acquire_target(String.t(), String.t(), term()) :: :ok | {:error, atom()}
    @callback begin_restore(map(), term()) :: :ok | {:error, atom()}
    @callback finalize_restore(map(), map(), String.t(), term()) ::
                {:ok, map()} | {:error, atom()}
  end

  @spec begin(map(), module(), term(), keyword()) ::
          {:ok, map()} | {:already_verified, map()} | {:refused, String.t()}
  def begin(input, port, context, options \\ [])

  def begin(input, port, context, options) when is_map(input) and is_atom(port) do
    with :ok <- validate_input(input),
         target_digest <- digest(input["target"]),
         verification_key <-
           {input["source_digest"], target_digest, input["verifier_version"]},
         :continue <- completed(port.lookup_completed(verification_key, context)),
         lease <- random_hex(options, 32),
         :ok <- acquire(port, target_digest, lease, context),
         run <- build_run(input, target_digest, verification_key, lease, options),
         :ok <- persist_begin(port, run, context) do
      {:ok, run}
    else
      {:already_verified, proof} -> {:already_verified, proof}
      {:refused, code} -> {:refused, code}
      {:error, :target_busy} -> {:refused, "target_busy"}
      {:error, _reason} -> {:refused, "restore_store_unavailable"}
    end
  end

  def begin(_input, _port, _context, _options), do: {:refused, "invalid_restore_request"}

  @spec finalize(map(), map(), module(), term(), keyword()) ::
          {:ok, map()} | {:refused, String.t()}
  def finalize(run, proof, port, context, options \\ [])

  def finalize(run, proof, port, context, options)
      when is_map(run) and is_map(proof) and is_atom(port) do
    with :ok <- valid_pending_run(run),
         :ok <- validate_proof(run, proof),
         {:ok, epoch} <- fresh_epoch(proof["old_sync_epoch"], options, 3),
         bounded <- bounded_proof(run, proof),
         {:ok, completed} <- port.finalize_restore(run, bounded, epoch, context),
         true <- completed[:sync_epoch] == epoch,
         true <- completed[:epoch_finalized] == true,
         true <- completed[:ready] == true do
      {:ok, completed}
    else
      {:refused, code} -> {:refused, code}
      {:error, reason} when is_atom(reason) -> {:refused, Atom.to_string(reason)}
      false -> {:refused, "non_atomic_finalization"}
      _ -> {:refused, "restore_store_unavailable"}
    end
  end

  def finalize(_run, _proof, _port, _context, _options),
    do: {:refused, "invalid_restore_run"}

  defp validate_input(input) do
    cond do
      input["target_class"] == "live" ->
        {:refused, "destination_live"}

      input["target_class"] != "empty_isolated" ->
        {:refused, "invalid_destination_class"}

      input["target_empty"] != true ->
        {:refused, "destination_nonempty"}

      input["source_target_distinct"] != true ->
        {:refused, "source_target_ambiguous"}

      input["wal_complete"] != true ->
        {:refused, "missing_wal"}

      input["source_verified"] != true ->
        {:refused, "source_unverified"}

      input["image_immutable"] != true or not valid_digest?(input["image_digest"]) ->
        {:refused, "mutable_image"}

      input["compatibility"] == "expired" and not valid_override?(input["recovery_override"]) ->
        {:refused, "compatibility_expired"}

      input["compatibility"] not in ["current", "expired"] ->
        {:refused, "compatibility_unverified"}

      input["production_side_effects"] != false ->
        {:refused, "production_side_effects_enabled"}

      not valid_digest?(input["source_digest"]) ->
        {:refused, "source_digest_invalid"}

      not (is_binary(input["target"]) and byte_size(input["target"]) in 1..256) ->
        {:refused, "target_invalid"}

      not positive_integer?(input["schema_version"]) or
        not positive_integer?(input["protocol_train"]) or
          not positive_integer?(input["verifier_version"]) ->
        {:refused, "compatibility_unverified"}

      not valid_uuid?(input["current_sync_epoch"]) ->
        {:refused, "stale_epoch"}

      not valid_timestamp?(input["recovery_point"]) or not valid_timestamp?(input["started_at"]) ->
        {:refused, "timestamp_invalid"}

      true ->
        :ok
    end
  end

  defp valid_pending_run(%{
         ready: false,
         epoch_finalized: false,
         lease: lease,
         target_digest: target_digest,
         verification_key: {_source, verification_target, _version}
       })
       when is_binary(lease) and target_digest == verification_target,
       do: :ok

  defp valid_pending_run(_run), do: {:refused, "invalid_restore_run"}

  defp validate_proof(run, proof) do
    semantic = proof["semantic"]

    cond do
      proof["manifest_verified"] != true ->
        {:refused, "corrupt_manifest"}

      proof["checksum_verified"] != true ->
        {:refused, "wrong_key_or_checksum"}

      not valid_uuid?(proof["old_sync_epoch"]) ->
        {:refused, "stale_epoch"}

      proof["old_sync_epoch"] != run.previous_sync_epoch ->
        {:refused, "stale_epoch"}

      not is_map(semantic) or Enum.any?(@semantic, &(semantic[&1] != true)) ->
        {:refused, "semantic_smoke_incomplete"}

      not valid_timestamp?(proof["finished_at"]) ->
        {:refused, "timestamp_invalid"}

      not non_negative_integer?(proof["duration_seconds"]) or
          not non_negative_integer?(proof["rpo_seconds"]) ->
        {:refused, "measurement_missing"}

      true ->
        :ok
    end
  end

  defp build_run(input, target_digest, verification_key, lease, options) do
    override = input["recovery_override"]

    %{
      compatibility: input["compatibility"],
      epoch_finalized: false,
      image_digest: input["image_digest"],
      lease: lease,
      outcome_code: "restore_started",
      override_code: if(is_map(override), do: override["reason"], else: nil),
      production_side_effects: false,
      previous_sync_epoch: input["current_sync_epoch"],
      protocol_train: input["protocol_train"],
      ready: false,
      recovery_point: input["recovery_point"],
      run_id: random_hex(options, 16),
      schema_version: input["schema_version"],
      source_digest: input["source_digest"],
      started_at: input["started_at"],
      target_digest: target_digest,
      verification_key: verification_key,
      verifier_version: input["verifier_version"]
    }
  end

  defp bounded_proof(run, proof) do
    %{
      duration_seconds: proof["duration_seconds"],
      epoch_finalized: true,
      finished_at: proof["finished_at"],
      manifest_checksum: "verified",
      outcome_code: "verified",
      ready: true,
      rpo_seconds: proof["rpo_seconds"],
      semantic_smoke: @semantic,
      source_digest: run.source_digest,
      target_digest: run.target_digest,
      verifier_version: run.verifier_version
    }
  end

  defp completed({:ok, proof}) when is_map(proof), do: {:already_verified, proof}
  defp completed(:error), do: :continue
  defp completed({:error, reason}), do: {:error, reason}
  defp completed(_unknown), do: {:error, :invalid_store_result}

  defp acquire(port, target_digest, lease, context) do
    case port.acquire_target(target_digest, lease, context) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_store_result}
    end
  end

  defp persist_begin(port, run, context) do
    case port.begin_restore(run, context) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_store_result}
    end
  end

  defp fresh_epoch(old_epoch, options, remaining) when remaining > 0 do
    epoch = uuid(random_bytes(options, 16))
    if epoch == old_epoch, do: fresh_epoch(old_epoch, options, remaining - 1), else: {:ok, epoch}
  end

  defp fresh_epoch(_old_epoch, _options, 0), do: {:refused, "epoch_rotation_failed"}

  defp uuid(<<a::32, b::16, c::16, d::16, e::48>>) do
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    Enum.join(
      [hex(a, 8), hex(b, 4), hex(c, 4), hex(d, 4), hex(e, 12)],
      "-"
    )
  end

  defp hex(value, width),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")

  defp random_hex(options, bytes),
    do: options |> random_bytes(bytes) |> Base.encode16(case: :lower)

  defp random_bytes(options, bytes) do
    generator = Keyword.get(options, :random_bytes, &:crypto.strong_rand_bytes/1)

    case generator.(bytes) do
      value when is_binary(value) and byte_size(value) == bytes -> value
      _ -> raise ArgumentError, "random byte generator returned an invalid length"
    end
  end

  defp digest(value),
    do: "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))

  defp valid_digest?(value), do: is_binary(value) and Regex.match?(@digest, value)
  defp positive_integer?(value), do: is_integer(value) and value >= 1
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp valid_timestamp?(value) when is_binary(value),
    do: match?({:ok, _, _}, DateTime.from_iso8601(value))

  defp valid_timestamp?(_value), do: false

  defp valid_uuid?(value) when is_binary(value), do: Regex.match?(@uuid_v4, value)
  defp valid_uuid?(_value), do: false

  defp valid_override?(
         %{
           "approved_at" => approved_at,
           "reason" => "expired_compatibility",
           "recorded" => true
         } = override
       ) do
    Map.keys(override) |> Enum.sort() == ~w(approved_at reason recorded) and
      valid_timestamp?(approved_at)
  end

  defp valid_override?(_override), do: false
end
