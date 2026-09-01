defmodule Keepling.Application.Sync.ReferenceModel do
  @moduledoc """
  Persistence-neutral reference reducer for Keepling offline synchronization.

  The reducer keeps canonical shadow, visible optimistic projection, mutation
  journal, dependency metadata, and outbox as separate durable values. It uses
  JSON-compatible string-keyed maps so the same vectors can be implemented by
  the later desktop and iPhone stores without sharing persistence records.
  """

  @terminal_outcomes ~w(accepted already_satisfied rejected stale conflict)

  @type state :: %{required(String.t()) => term()}

  @spec new() :: state()
  def new do
    %{
      "canonical_shadow" => %{},
      "visible" => %{},
      "journal" => %{},
      "dependencies" => %{},
      "outbox" => [],
      "cursor" => nil,
      "fence" => nil
    }
  end

  @spec local_accept(state(), map()) ::
          {:ok, String.t(), state()} | {:error, atom(), state()}
  def local_accept(state, mutation) when is_map(state) and is_map(mutation) do
    with :ok <- validate_mutation(mutation),
         false <- Map.has_key?(state["journal"], mutation["mutation_id"]) do
      mutation_id = mutation["mutation_id"]

      journal_entry = %{
        "accepted_at" => mutation["accepted_at"],
        "command_bytes" => mutation["command_bytes"],
        "fingerprint" => mutation["fingerprint"],
        "outcome" => "pending",
        "resource_keys" => mutation["resource_keys"]
      }

      next =
        state
        |> put_in(["journal", mutation_id], journal_entry)
        |> put_in(["dependencies", mutation_id], mutation["dependencies"])
        |> Map.update!("outbox", &(&1 ++ [mutation]))
        |> replay_visible()

      {:ok, "local_saved", next}
    else
      true -> {:error, :mutation_identity_reused, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  def local_accept(state, _mutation), do: {:error, :invalid_mutation, state}

  @spec pull(state(), map()) :: {:ok, state()} | {:error, atom(), state()}
  def pull(state, %{"cursor" => cursor, "changes" => changes})
      when is_binary(cursor) and is_list(changes) do
    with {:ok, shadow} <- apply_changes(state["canonical_shadow"], changes) do
      next = state |> Map.put("canonical_shadow", shadow) |> Map.put("cursor", cursor)
      {:ok, replay_visible(next)}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def pull(state, _page), do: {:error, :invalid_pull, state}

  @spec ready_pushes(state()) :: [map()]
  def ready_pushes(%{"fence" => fence}) when not is_nil(fence), do: []
  def ready_pushes(%{"outbox" => outbox}) when is_list(outbox), do: outbox

  @spec acknowledge(state(), map()) ::
          {:ok, state()} | {:error, atom(), state()}
  def acknowledge(state, acknowledgement) when is_map(acknowledgement) do
    mutation_id = acknowledgement["mutation_id"]

    case Enum.find(state["outbox"], &(&1["mutation_id"] == mutation_id)) do
      nil ->
        {:error, :unknown_mutation, state}

      mutation ->
        settle_acknowledgement(state, mutation, acknowledgement)
    end
  end

  def acknowledge(state, _acknowledgement), do: {:error, :invalid_acknowledgement, state}

  @spec fence(state(), String.t()) :: {:ok, state()}
  def fence(state, reason) when is_binary(reason) and byte_size(reason) > 0 do
    {:ok, Map.put(state, "fence", reason)}
  end

  @spec bootstrap(state(), map()) :: {:ok, state()} | {:error, atom(), state()}
  def bootstrap(state, %{"cursor" => cursor, "entities" => entities})
      when is_binary(cursor) and is_list(entities) do
    with {:ok, shadow} <- apply_changes(%{}, entities) do
      next = state |> Map.put("canonical_shadow", shadow) |> Map.put("cursor", cursor)
      {:ok, replay_visible(next)}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def bootstrap(state, _snapshot), do: {:error, :invalid_bootstrap, state}

  defp settle_acknowledgement(state, mutation, acknowledgement) do
    with true <- exact_match?(mutation, acknowledgement),
         true <- acknowledgement["outcome"] in @terminal_outcomes,
         {:ok, shadow} <- apply_acknowledgement_snapshot(state, mutation, acknowledgement) do
      mutation_id = mutation["mutation_id"]

      terminal_entry =
        state["journal"][mutation_id]
        |> Map.put("outcome", acknowledgement["outcome"])
        |> Map.put("terminal_snapshot", acknowledgement["snapshot"])

      next =
        state
        |> Map.put("canonical_shadow", shadow)
        |> put_in(["journal", mutation_id], terminal_entry)
        |> Map.update!(
          "outbox",
          &Enum.reject(&1, fn queued -> queued["mutation_id"] == mutation_id end)
        )
        |> replay_visible()

      {:ok, next}
    else
      false -> {:error, :acknowledgement_mismatch, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp exact_match?(mutation, acknowledgement) do
    mutation["mutation_id"] == acknowledgement["mutation_id"] and
      secure_equal?(mutation["fingerprint"], acknowledgement["fingerprint"])
  end

  defp secure_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right),
       do: :crypto.hash_equals(left, right)

  defp secure_equal?(_left, _right), do: false

  defp validate_mutation(mutation) do
    with mutation_id when is_binary(mutation_id) and byte_size(mutation_id) > 0 <-
           mutation["mutation_id"],
         command_bytes when is_binary(command_bytes) and byte_size(command_bytes) > 0 <-
           mutation["command_bytes"],
         fingerprint when is_binary(fingerprint) <- mutation["fingerprint"],
         ^fingerprint <- digest(command_bytes),
         resource_keys when is_list(resource_keys) and resource_keys != [] <-
           mutation["resource_keys"],
         true <- Enum.all?(resource_keys, &(is_binary(&1) and byte_size(&1) > 0)),
         true <- resource_keys == resource_keys |> Enum.uniq() |> Enum.sort(),
         dependencies when is_list(dependencies) <- mutation["dependencies"],
         true <- Enum.all?(dependencies, &is_binary/1),
         %{"entity_id" => entity_id, "snapshot" => snapshot}
         when is_binary(entity_id) and is_map(snapshot) <- mutation["effect"],
         accepted_at when is_binary(accepted_at) <- mutation["accepted_at"] do
      :ok
    else
      _invalid -> {:error, :invalid_mutation}
    end
  end

  defp digest(command_bytes) do
    :crypto.hash(:sha256, command_bytes) |> Base.encode16(case: :lower)
  end

  defp apply_changes(shadow, changes) do
    Enum.reduce_while(changes, {:ok, shadow}, fn change, {:ok, current} ->
      case change do
        %{"entity_id" => entity_id, "snapshot" => %{"revision" => revision} = snapshot}
        when is_binary(entity_id) and is_integer(revision) and revision >= 0 ->
          existing_revision = get_in(current, [entity_id, "revision"]) || -1

          next =
            if revision >= existing_revision,
              do: Map.put(current, entity_id, snapshot),
              else: current

          {:cont, {:ok, next}}

        _invalid ->
          {:halt, {:error, :invalid_change}}
      end
    end)
  end

  defp apply_acknowledgement_snapshot(state, mutation, %{"snapshot" => snapshot})
       when is_map(snapshot) do
    apply_changes(state["canonical_shadow"], [
      %{"entity_id" => mutation["effect"]["entity_id"], "snapshot" => snapshot}
    ])
  end

  defp apply_acknowledgement_snapshot(_state, _mutation, _acknowledgement),
    do: {:error, :invalid_acknowledgement}

  defp replay_visible(state) do
    visible =
      Enum.reduce(state["outbox"], state["canonical_shadow"], fn mutation, projection ->
        Map.put(
          projection,
          mutation["effect"]["entity_id"],
          mutation["effect"]["snapshot"]
        )
      end)

    Map.put(state, "visible", visible)
  end
end
