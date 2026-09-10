defmodule Keepling.Adapters.Postgres.Preview do
  @moduledoc """
  PostgreSQL implementation of `Keepling.Application.Preview.Port`.

  `apply_all/4` runs exactly ONE `Repo.transaction`: replay detection first
  (a commit retried with the same mutation identity returns the original
  stored result and performs no second write), then `SELECT ... FOR UPDATE`
  every target row in deterministic `task_id` order (so two concurrent
  commits over overlapping target sets cannot deadlock), then re-reads the
  live sync epoch, then calls the `authorize` callback (always
  `Keepling.Application.Preview.authorize_commit/2` in production) against
  the live-read authoritative state. Only if that returns `:ok` does it
  apply every target's command through the SAME
  `Keepling.Application.Commands.dispatch/3` /
  `Keepling.Application.Undo.dispatch/3` path every other adapter uses --
  so activity and undo handles are written exactly as they are for a human
  client (T-05-37). Any mismatch rolls back the whole transaction before a
  single write -- there is no per-target success shape (D-18).
  """

  @behaviour Keepling.Application.Preview.Port

  alias Ecto.Adapters.SQL
  alias Keepling.Application.{Commands, Preview, Undo}
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Repo

  @impl true
  def current_sync_epoch(_context) do
    case SQL.query(
           Repo,
           "SELECT epoch FROM sync_epochs WHERE singleton_key = TRUE AND finalized = TRUE",
           []
         ) do
      {:ok, %{rows: [[epoch]]}} -> {:ok, Ecto.UUID.load!(epoch)}
      {:ok, %{rows: []}} -> {:error, :sync_epoch_unavailable}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :infrastructure_failure}
  end

  @impl true
  def lock_targets(context, _binding, targets) do
    account_id = context.account_id

    targets
    |> Enum.sort_by(& &1.task_id)
    |> Enum.reduce_while({:ok, []}, fn target, {:ok, acc} ->
      case SQL.query!(
             Repo,
             "SELECT revision FROM tasks WHERE account_id = $1 AND id = $2 FOR UPDATE",
             [account_id, Ecto.UUID.dump!(target.task_id)]
           ).rows do
        [[revision]] ->
          {:cont, {:ok, [%{task_id: target.task_id, expected_revision: revision} | acc]}}

        [] ->
          {:halt, {:error, :preview_stale}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, acc |> Enum.reverse() |> Enum.sort_by(& &1.task_id)}
      error -> error
    end
  end

  @impl true
  def apply_all(binding, mutation_id, context, authorize) do
    case Repo.transaction(fn ->
           case do_apply_all(binding, mutation_id, context, authorize) do
             {:ok, result} -> result
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :infrastructure_failure}
  end

  defp do_apply_all(binding, mutation_id, context, authorize) do
    targets = Enum.sort_by(binding.targets, & &1.task_id)

    derived =
      Enum.map(targets, fn target ->
        {target.task_id, target.expected_revision,
         derive_mutation_id(mutation_id, target.task_id)}
      end)

    case replay_results(derived, context) do
      {:ok, results} ->
        {:ok, %{mutation_id: mutation_id, results: results}}

      {:error, reason} ->
        {:error, reason}

      :not_replayed ->
        with {:ok, live_targets} <- lock_targets(context, binding, targets),
             {:ok, epoch} <- current_sync_epoch(context) do
          authoritative = %{
            account_id: context.account_id,
            arguments: binding.arguments,
            command: binding.command,
            server_instance: Preview.server_instance(),
            sync_epoch: epoch,
            targets: live_targets
          }

          case authorize.(binding, authoritative) do
            :ok -> apply_targets(binding.command, mutation_id, derived, context)
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  # A commit retried with the same (token, mutation_id) pair derives the
  # exact same per-target mutation identities; if EVERY one already has a
  # terminal receipt, this commit already happened -- return the original
  # stored results, write nothing, and never re-run the lock/authorize
  # gate (which would otherwise (wrongly) see the now-advanced live
  # revisions as drift and refuse a legitimate replay).
  defp replay_results(derived, context) do
    outcomes =
      Enum.map(derived, fn {task_id, _expected_revision, target_mutation_id} ->
        case Commands.lookup_result(context, target_mutation_id, CommandStore) do
          {:ok, %{body: body}} -> {:ok, %{task_id: task_id, revision: Map.get(body, "revision")}}
          {:error, :not_found} -> :not_found
          {:error, reason} -> {:error, reason}
        end
      end)

    cond do
      Enum.all?(outcomes, &match?({:ok, _result}, &1)) ->
        {:ok, Enum.map(outcomes, fn {:ok, result} -> result end)}

      Enum.any?(outcomes, &match?({:error, _reason}, &1)) ->
        {:error, :infrastructure_failure}

      true ->
        :not_replayed
    end
  end

  defp apply_targets(command_str, mutation_id, derived, context) do
    command_type = String.to_existing_atom(command_str)

    results =
      Enum.map(derived, fn {task_id, expected_revision, target_mutation_id} ->
        {task_id,
         dispatch_target(command_type, task_id, expected_revision, target_mutation_id, context)}
      end)

    if Enum.all?(results, fn {_task_id, outcome} -> match?({:ok, _body}, outcome) end) do
      mapped =
        Enum.map(results, fn {task_id, {:ok, body}} ->
          %{task_id: task_id, revision: Map.get(body, "revision")}
        end)

      {:ok, %{mutation_id: mutation_id, results: mapped}}
    else
      # Structurally should not happen: every target's live revision was
      # just verified to match the binding under row locks held for the
      # remainder of this transaction. If a domain-level refusal still
      # occurs (e.g. a lifecycle rule this preview's binding did not
      # anticipate), treat it exactly like drift -- roll back everything
      # rather than represent a partial success.
      {:error, :preview_stale}
    end
  end

  defp dispatch_target(command_type, task_id, expected_revision, mutation_id, context)
       when command_type in [:trash_task, :restore_task] do
    command = %{
      expected_revision: expected_revision,
      mutation_id: mutation_id,
      task_id: task_id,
      type: command_type,
      version: 1
    }

    case Commands.dispatch(command, context, CommandStore) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch_target(:undo_task, task_id, expected_revision, mutation_id, context) do
    with {:ok, handle} <- resolve_undo_handle(context.account_id, task_id, expected_revision) do
      command = %{handle: handle, mutation_id: mutation_id, type: :undo_task, version: 1}

      case Undo.dispatch(command, context, CommandStore) do
        {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
        {:ok, %{body: body}} -> {:error, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp resolve_undo_handle(account_id, task_id, expected_revision) do
    case SQL.query!(
           Repo,
           """
           SELECT id, produced_revision FROM undo_handles
           WHERE account_id = $1 AND task_id = $2 AND state = 'available'
           ORDER BY inserted_at DESC
           FOR UPDATE
           LIMIT 1
           """,
           [account_id, Ecto.UUID.dump!(task_id)]
         ).rows do
      [[raw_id, produced_revision]] when produced_revision == expected_revision ->
        {:ok, raw_undo_handle(raw_id)}

      [[_raw_id, _produced_revision]] ->
        {:error, :preview_stale}

      [] ->
        {:error, :preview_stale}
    end
  end

  # Byte-identical to CommandStore's private raw_undo_handle/1 formula:
  # HMAC-SHA256 over the handle's raw 16-byte id, keyed by the same
  # endpoint secret_key_base, url-safe base64 without padding. Reproducing
  # this (rather than exposing the original as public API) lets a bulk
  # undo commit resolve the SAME handle a single-target undo would.
  defp raw_undo_handle(raw_id) do
    secret =
      Application.fetch_env!(:keepling, KeeplingWeb.Endpoint) |> Keyword.fetch!(:secret_key_base)

    :crypto.mac(:hmac, :sha256, secret, raw_id) |> Base.url_encode64(padding: false)
  end

  defp derive_mutation_id(mutation_id, task_id) do
    <<raw::binary-size(16), _rest::binary>> = :crypto.hash(:sha256, mutation_id <> ":" <> task_id)
    Ecto.UUID.load!(raw)
  end
end
