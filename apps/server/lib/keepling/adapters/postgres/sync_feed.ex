defmodule Keepling.Adapters.Postgres.SyncFeed do
  @moduledoc """
  PostgreSQL persistence for the account-scoped ordered synchronization feed.

  A command transaction reserves its account sequence before locking semantic
  resources, then writes deterministic ordinals before finalizing the receipt.
  Sequence allocation and every envelope therefore roll back with the command.
  """

  alias Ecto.Adapters.SQL
  alias Keepling.Repo

  @maximum_page_size 200

  @authorization_fields [
    :issuer,
    :origin,
    :server_instance,
    :subject,
    :generation,
    :sync_epoch,
    :protocol_train
  ]

  @spec authorize_namespace(map(), map()) :: :ok | {:error, :namespace_mismatch}
  def authorize_namespace(supplied, authoritative)
      when is_map(supplied) and is_map(authoritative) do
    if Map.take(supplied, @authorization_fields) ==
         Map.take(authoritative, @authorization_fields) and
         Enum.all?(@authorization_fields, &Map.has_key?(supplied, &1)) and
         Enum.all?(@authorization_fields, &Map.has_key?(authoritative, &1)) do
      :ok
    else
      {:error, :namespace_mismatch}
    end
  end

  def authorize_namespace(_supplied, _authoritative), do: {:error, :namespace_mismatch}

  @spec authorize_bootstrap(map()) :: :ok | {:error, atom()}
  def authorize_bootstrap(%{
        account_id: account_id,
        namespace: supplied,
        authoritative_namespace: authoritative
      }) do
    with :ok <- authorize_namespace(supplied, authoritative),
         {:ok, account_subject} <- Ecto.UUID.load(account_id),
         true <- account_subject == authoritative.subject do
      :ok
    else
      _ -> {:error, :namespace_mismatch}
    end
  end

  def authorize_bootstrap(_context), do: {:error, :namespace_mismatch}

  @spec capture_high_water(map()) :: {:ok, map()} | {:error, atom()}
  def capture_high_water(context) do
    with :ok <- authorize_bootstrap(context),
         {:ok, %{rows: rows}} <-
           SQL.query(
             Repo,
             """
             SELECT sequence, ordinal
             FROM sync_changes
             WHERE account_id = $1
             ORDER BY sequence DESC, ordinal DESC
             LIMIT 1
             """,
             [context.account_id]
           ) do
      case rows do
        [[sequence, ordinal]] -> {:ok, %{sequence: sequence, ordinal: ordinal}}
        [] -> {:ok, %{sequence: 0, ordinal: -1}}
      end
    else
      {:error, :namespace_mismatch} -> {:error, :namespace_mismatch}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @spec bootstrap_page(map(), map(), nil | map(), pos_integer()) ::
          {:ok, map()} | {:error, atom()}
  def bootstrap_page(context, high_water, keyset, limit)
      when is_integer(limit) and limit >= 1 and limit <= 100 do
    with :ok <- authorize_bootstrap(context),
         {entity_type, entity_id} <- bootstrap_keyset(keyset),
         {:ok, %{rows: rows}} <-
           SQL.query(
             Repo,
             bootstrap_query(),
             [context.account_id, entity_type, dump_optional_uuid(entity_id), limit + 1]
           ) do
      {page_rows, extra_rows} = Enum.split(rows, limit)
      entities = Enum.map(page_rows, &bootstrap_entity/1)

      next_keyset =
        case {List.last(entities), extra_rows} do
          {%{"entity_id" => id, "entity_type" => type}, [_extra | _]} ->
            %{entity_type: type, entity_id: id}

          _ ->
            nil
        end

      {:ok, %{entities: entities, high_water: high_water, next_keyset: next_keyset}}
    else
      {:error, :namespace_mismatch} -> {:error, :namespace_mismatch}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def bootstrap_page(_context, _high_water, _keyset, _limit), do: {:error, :invalid_limit}

  @spec reserve_sequence(Ecto.Repo.t(), binary(), DateTime.t()) :: {:ok, pos_integer()}
  def reserve_sequence(repo, account_id, accepted_at) do
    SQL.query!(
      repo,
      """
      INSERT INTO sync_accounts (
        account_id, high_sequence, low_water_sequence, low_water_ordinal,
        inserted_at, updated_at
      )
      VALUES ($1, 0, 0, -1, $2, $2)
      ON CONFLICT (account_id) DO NOTHING
      """,
      [account_id, accepted_at]
    )

    %{rows: [[sequence]]} =
      SQL.query!(
        repo,
        """
        UPDATE sync_accounts
        SET high_sequence = high_sequence + 1, updated_at = $2
        WHERE account_id = $1
        RETURNING high_sequence
        """,
        [account_id, accepted_at]
      )

    {:ok, sequence}
  end

  @spec append_terminal(Ecto.Repo.t(), binary(), pos_integer(), map(), map(), DateTime.t()) ::
          :ok
  def append_terminal(repo, account_id, sequence, command, result, accepted_at) do
    result
    |> terminal_envelopes(command)
    |> Enum.with_index()
    |> Enum.each(fn {envelope, ordinal} ->
      %{num_rows: 1} =
        SQL.query!(
          repo,
          """
          INSERT INTO sync_changes (
            account_id, sequence, ordinal, mutation_id, kind, entity_type,
            entity_id, entity_revision, payload, inserted_at
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10)
          """,
          [
            account_id,
            sequence,
            ordinal,
            dump_uuid(command.mutation_id),
            envelope.kind,
            envelope.entity_type,
            dump_optional_uuid(envelope.entity_id),
            envelope.entity_revision,
            envelope.payload,
            accepted_at
          ]
        )
    end)

    :ok
  end

  @spec list_after(binary(), nil | map(), pos_integer()) :: {:ok, map()} | {:error, atom()}
  def list_after(account_id, position, limit)
      when is_integer(limit) and limit >= 1 and limit <= @maximum_page_size do
    {sequence, ordinal} = position_values(position)

    case SQL.query(
           Repo,
           """
           SELECT sequence, ordinal, mutation_id, kind, entity_type, entity_id,
                  entity_revision, payload, inserted_at
           FROM sync_changes
           WHERE account_id = $1
             AND (sequence, ordinal) > ($2, $3)
           ORDER BY sequence ASC, ordinal ASC
           LIMIT $4
           """,
           [account_id, sequence, ordinal, limit]
         ) do
      {:ok, %{rows: rows}} ->
        changes = Enum.map(rows, &change_from_row/1)

        {:ok,
         %{
           changes: changes,
           high_water: position_of(List.last(changes))
         }}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def list_after(_account_id, _position, _limit), do: {:error, :invalid_limit}

  defp terminal_envelopes(result, command) do
    body = result.body

    [
      %{
        kind: "command_outcome",
        entity_type: "command",
        entity_id: command.mutation_id,
        entity_revision: nil,
        payload: %{"status" => result.status, "result" => body}
      }
    ]
    |> maybe_append_snapshot(body)
    |> maybe_append_conflict(body)
    |> maybe_append_collection_tombstones(command, body)
    |> maybe_append_undo(body)
  end

  defp maybe_append_snapshot(envelopes, %{"snapshot" => snapshot} = body)
       when is_map(snapshot) do
    cond do
      is_binary(body["task_id"]) ->
        envelopes ++
          [
            %{
              kind: "task_snapshot",
              entity_type: "task",
              entity_id: body["task_id"],
              entity_revision: body["revision"],
              payload: snapshot
            }
          ]

      is_binary(body["organization_id"]) ->
        envelopes ++
          [
            %{
              kind: "organization_snapshot",
              entity_type: "organization",
              entity_id: body["organization_id"],
              entity_revision: body["revision"],
              payload: snapshot
            }
          ]

      true ->
        envelopes
    end
  end

  defp maybe_append_snapshot(envelopes, _body), do: envelopes

  defp maybe_append_conflict(envelopes, %{"conflict" => conflict} = body)
       when is_map(conflict) do
    envelopes ++
      [
        %{
          kind: "conflict_snapshot",
          entity_type: "conflict",
          entity_id: conflict["id"],
          entity_revision: conflict["latest_revision"] || body["current_revision"],
          payload: conflict
        }
      ]
  end

  defp maybe_append_conflict(envelopes, _body), do: envelopes

  defp maybe_append_collection_tombstones(
         envelopes,
         %{type: :assign_task_organizations} = command,
         %{"outcome" => outcome} = body
       )
       when outcome in ["accepted", "already_satisfied"] do
    removed_project =
      case {command.base_values.project_id, command.fields.project_id} do
        {project_id, replacement} when is_binary(project_id) and project_id != replacement ->
          [
            collection_tombstone(
              "task_project",
              project_id,
              command.task_id,
              project_id,
              body["revision"]
            )
          ]

        _ ->
          []
      end

    removed_tags =
      command.base_values.tag_ids
      |> MapSet.new()
      |> MapSet.difference(MapSet.new(command.fields.tag_ids))
      |> Enum.sort()
      |> Enum.map(fn tag_id ->
        collection_tombstone(
          "task_tags",
          tag_id,
          command.task_id,
          tag_id,
          body["revision"]
        )
      end)

    envelopes ++ removed_project ++ removed_tags
  end

  defp maybe_append_collection_tombstones(envelopes, _command, _body), do: envelopes

  defp collection_tombstone(collection, entity_id, task_id, organization_id, revision) do
    %{
      kind: "collection_tombstone",
      entity_type: "collection_membership",
      entity_id: entity_id,
      entity_revision: revision,
      payload: %{
        "collection" => collection,
        "organization_id" => organization_id,
        "task_id" => task_id
      }
    }
  end

  defp maybe_append_undo(envelopes, %{"undo" => undo}) when is_map(undo) do
    envelopes ++
      [
        %{
          kind: "undo_metadata",
          entity_type: "undo",
          entity_id: undo["id"],
          entity_revision: nil,
          payload: Map.drop(undo, ["handle"])
        }
      ]
  end

  defp maybe_append_undo(envelopes, _body), do: envelopes

  defp position_values(nil), do: {0, -1}

  defp position_values(%{sequence: sequence, ordinal: ordinal})
       when is_integer(sequence) and sequence >= 0 and is_integer(ordinal) and ordinal >= -1,
       do: {sequence, ordinal}

  defp position_values(_invalid), do: raise(ArgumentError, "invalid feed position")

  defp bootstrap_keyset(nil), do: {nil, nil}

  defp bootstrap_keyset(%{entity_type: entity_type, entity_id: entity_id})
       when entity_type in ["organization", "task"] and is_binary(entity_id),
       do: {entity_type, entity_id}

  defp bootstrap_keyset(_invalid), do: raise(ArgumentError, "invalid bootstrap keyset")

  defp bootstrap_query do
    """
    WITH canonical_entities AS (
      SELECT
        'organization'::text AS entity_type,
        organizations.id AS entity_id,
        organizations.revision AS entity_revision,
        jsonb_build_object(
          'id', organizations.id::text,
          'kind', organizations.kind,
          'name', organizations.display_name,
          'archived_at', organizations.archived_at,
          'revision', organizations.revision
        ) AS snapshot
      FROM organizations
      WHERE organizations.account_id = $1

      UNION ALL

      SELECT
        'task'::text AS entity_type,
        tasks.id AS entity_id,
        tasks.revision AS entity_revision,
        jsonb_build_object(
          'id', tasks.id::text,
          'title', tasks.title,
          'notes', tasks.notes,
          'inbox_state', tasks.inbox_state,
          'revision', tasks.revision,
          'captured_at', tasks.captured_at,
          'planned_on', tasks.planned_on,
          'deadline_on', tasks.deadline_on,
          'completed_at', tasks.completed_at,
          'trashed_at', tasks.trashed_at,
          'project_id', tasks.project_id,
          'tag_ids', COALESCE(
            (
              SELECT jsonb_agg(task_tags.tag_id::text ORDER BY task_tags.tag_id)
              FROM task_tags
              WHERE task_tags.account_id = tasks.account_id
                AND task_tags.task_id = tasks.id
            ),
            '[]'::jsonb
          )
        ) AS snapshot
      FROM tasks
      WHERE tasks.account_id = $1
    )
    SELECT entity_type, entity_id, entity_revision, snapshot
    FROM canonical_entities
    WHERE $2::text IS NULL OR (entity_type, entity_id) > ($2::text, $3::uuid)
    ORDER BY entity_type ASC, entity_id ASC
    LIMIT $4
    """
  end

  defp bootstrap_entity([entity_type, entity_id, entity_revision, snapshot]) do
    %{
      "entity_id" => load_uuid(entity_id),
      "entity_type" => entity_type,
      "kind" => "#{entity_type}_snapshot",
      "snapshot" => Map.put(snapshot, "revision", entity_revision)
    }
  end

  defp change_from_row([
         sequence,
         ordinal,
         mutation_id,
         kind,
         entity_type,
         entity_id,
         entity_revision,
         payload,
         inserted_at
       ]) do
    %{
      sequence: sequence,
      ordinal: ordinal,
      mutation_id: load_uuid(mutation_id),
      kind: kind,
      entity_type: entity_type,
      entity_id: load_optional_uuid(entity_id),
      entity_revision: entity_revision,
      payload: payload,
      inserted_at: to_datetime(inserted_at)
    }
  end

  defp position_of(nil), do: nil
  defp position_of(change), do: %{sequence: change.sequence, ordinal: change.ordinal}

  defp dump_uuid(value), do: Ecto.UUID.dump!(value)
  defp dump_optional_uuid(nil), do: nil
  defp dump_optional_uuid(value), do: dump_uuid(value)
  defp load_uuid(value), do: Ecto.UUID.load!(value)
  defp load_optional_uuid(nil), do: nil
  defp load_optional_uuid(value), do: load_uuid(value)
  defp to_datetime(%DateTime{} = value), do: value
  defp to_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
