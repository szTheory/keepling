defmodule Keepling.Application.Activity do
  @moduledoc """
  Closed application contract for canonical accepted task activity.

  Activity is append-only user data. It is queried through an account-bound,
  task-bound, revision-aware keyset cursor and remains distinct from command
  receipts, security audit records, and diagnostic telemetry.
  """

  @cursor_version 1
  @cursor_mac_bytes 32
  @default_limit 20
  @maximum_limit 50

  @activity_types ~w(
    task_captured
    task_details_updated
    task_planned
    task_unplanned
    task_clarified
    task_returned_to_inbox
    task_completed
    task_reopened
    task_trashed
    task_restored
    task_undo_applied
  )

  @type keyset :: %{
          accepted_at: DateTime.t(),
          activity_id: pos_integer(),
          view_revision: pos_integer()
        }

  defmodule Port do
    @moduledoc "Persistence port for account-scoped accepted activity queries."

    @callback list_task_activity(map(), String.t(), map()) ::
                {:ok, map()} | {:error, :infrastructure_failure | :not_found | :stale_cursor}
  end

  @spec activity_types() :: [String.t()]
  def activity_types, do: @activity_types

  @spec list_task(map(), String.t(), map(), module()) :: tuple()
  def list_task(context, task_id, options, port) do
    with {:ok, limit} <- limit(options),
         {:ok, cursor} <- cursor(options, context, task_id),
         {:ok, page} <-
           port.list_task_activity(context, task_id, %{cursor: cursor, limit: limit}) do
      {:ok, present_page(page, context, task_id)}
    end
  end

  @spec encode_cursor(keyset(), map()) :: String.t()
  def encode_cursor(keyset, context) do
    payload =
      :erlang.term_to_binary(
        {
          @cursor_version,
          context.account_id,
          context.task_id,
          DateTime.to_unix(keyset.accepted_at, :microsecond),
          keyset.activity_id,
          keyset.view_revision
        },
        [:deterministic]
      )

    mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload)
    Base.url_encode64(payload <> mac, padding: false)
  end

  @spec decode_cursor(String.t(), map()) :: {:ok, keyset()} | {:error, :invalid_cursor}
  def decode_cursor(cursor, context) when is_binary(cursor) and byte_size(cursor) <= 1024 do
    with {:ok, signed} <- Base.url_decode64(cursor, padding: false),
         true <- byte_size(signed) > @cursor_mac_bytes,
         payload_size = byte_size(signed) - @cursor_mac_bytes,
         <<payload::binary-size(^payload_size), supplied_mac::binary-size(@cursor_mac_bytes)>> <-
           signed,
         expected_mac = :crypto.mac(:hmac, :sha256, context.cursor_secret, payload),
         true <- :crypto.hash_equals(supplied_mac, expected_mac),
         {@cursor_version, account_id, task_id, accepted_at_us, activity_id, view_revision} <-
           :erlang.binary_to_term(payload, [:safe]),
         true <- account_id == context.account_id,
         true <- task_id == context.task_id,
         true <- is_integer(accepted_at_us),
         true <- is_integer(activity_id) and activity_id > 0,
         true <- is_integer(view_revision) and view_revision > 0,
         {:ok, accepted_at} <- DateTime.from_unix(accepted_at_us, :microsecond) do
      {:ok,
       %{
         accepted_at: accepted_at,
         activity_id: activity_id,
         view_revision: view_revision
       }}
    else
      _ -> {:error, :invalid_cursor}
    end
  rescue
    _error -> {:error, :invalid_cursor}
  end

  def decode_cursor(_cursor, _context), do: {:error, :invalid_cursor}

  defp limit(options) do
    case Map.get(options, :limit, @default_limit) do
      limit when is_integer(limit) and limit >= 1 and limit <= @maximum_limit -> {:ok, limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp cursor(options, context, task_id) do
    case Map.get(options, :cursor) do
      nil -> {:ok, nil}
      encoded -> decode_cursor(encoded, Map.put(context, :task_id, task_id))
    end
  end

  defp present_page(page, context, task_id) do
    next_cursor =
      case page.next_keyset do
        nil ->
          nil

        keyset ->
          encode_cursor(
            Map.put(keyset, :view_revision, page.view_revision),
            Map.put(context, :task_id, task_id)
          )
      end

    %{
      account_timezone: page.account_timezone,
      items: Enum.map(page.facts, &present_fact/1),
      next_cursor: next_cursor
    }
  end

  defp present_fact(fact) do
    %{
      accepted_at: DateTime.to_iso8601(fact.accepted_at),
      activity_id: fact.activity_id,
      actor: %{
        label: fact.actor_label,
        principal: fact.actor_principal,
        type: fact.actor_type
      },
      changes: present_changes(fact.changed_fields, fact.organization_references),
      client_kind: fact.client_kind,
      from_revision: fact.from_revision,
      mutation_id: fact.mutation_id,
      outcome: "accepted",
      recovery_state: fact.recovery_state,
      to_revision: fact.to_revision,
      type: fact.type,
      undone_activity_id: fact.undone_activity_id,
      version: fact.version
    }
  end

  defp present_changes(changed_fields, organization_references) do
    changed_fields
    |> Enum.map(fn {field, delta} ->
      present_change(to_string(field), delta, organization_references)
    end)
    |> Enum.sort_by(& &1.field)
  end

  defp present_change(field, delta, _refs) when field in ["notes", "title"] do
    %{field: field, kind: "text", new: delta_value(delta, "new"), old: delta_value(delta, "old")}
  end

  defp present_change("inbox_state", delta, _refs) do
    %{
      field: "inbox_state",
      kind: "state",
      new: delta_value(delta, "new"),
      old: delta_value(delta, "old")
    }
  end

  defp present_change(field, delta, _refs)
       when field in ["completed_at", "trashed_at"] do
    %{
      field: field,
      kind: "instant",
      new: delta_value(delta, "new"),
      old: delta_value(delta, "old")
    }
  end

  defp present_change(field, delta, _refs) when field in ["deadline_on", "planned_on"] do
    %{field: field, kind: "date", new: delta_value(delta, "new"), old: delta_value(delta, "old")}
  end

  defp present_change("project_id", delta, refs) do
    %{
      field: "project",
      kind: "organization",
      new: organization_reference(delta_value(delta, "new"), refs),
      old: organization_reference(delta_value(delta, "old"), refs)
    }
  end

  defp present_change("tag_ids", delta, refs) do
    %{
      field: "tags",
      kind: "organizations",
      new: organization_references(delta_value(delta, "new"), refs),
      old: organization_references(delta_value(delta, "old"), refs)
    }
  end

  defp present_change(field, delta, _refs) do
    %{field: field, kind: "state", new: delta_value(delta, "new"), old: delta_value(delta, "old")}
  end

  defp delta_value(delta, "new"),
    do: Map.get(delta, "new", Map.get(delta, :new, Map.get(delta, "to", Map.get(delta, :to))))

  defp delta_value(delta, "old"),
    do: Map.get(delta, "old", Map.get(delta, :old, Map.get(delta, "from", Map.get(delta, :from))))

  defp organization_reference(nil, _refs), do: nil
  defp organization_reference(id, refs), do: Map.fetch!(refs, id)

  defp organization_references(ids, refs) when is_list(ids),
    do: Enum.map(ids, &organization_reference(&1, refs))

  defp organization_references(nil, _refs), do: []
end
