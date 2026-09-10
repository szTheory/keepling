defmodule KeeplingWeb.MCP.Tools do
  @moduledoc """
  `tools/list` and `tools/call`. MCP-02's closed four write tools --
  `keepling.capture_task`, `keepling.update_task`, `keepling.complete_task`,
  `keepling.reopen_task` -- dispatch through the same
  `Keepling.Application.Commands.dispatch/3` every other adapter calls
  (D-01/D-02). `keepling.preview_bulk_change`/`keepling.commit_bulk_change`
  are declared in the generated schema (05-05-PLAN.md Task 1) but are
  intentionally absent from `tools/list` and `call/2` until plan 05-07
  implements them -- a tool listed but not executable is worse than one
  that is absent.
  """

  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias KeeplingWeb.MCP.{Errors, Scope, ToolSchemas}

  @capture_task_keys ~w(mutation_id task_id title version)
  @lifecycle_keys ~w(expected_revision mutation_id task_id version)
  @update_task_required_keys ~w(expected_revision mutation_id task_id version)
  @update_task_optional_keys ~w(title notes project_id tag_ids deadline_on planned_on)

  @implemented_tools [
    %{
      name: "keepling.capture_task",
      description: "Capture exactly one new task by stable opaque identity."
    },
    %{
      name: "keepling.update_task",
      description:
        "Edit title, notes, project/tags, or the v1 temporal fields of exactly one task."
    },
    %{
      name: "keepling.complete_task",
      description: "Complete exactly one task by stable opaque identity."
    },
    %{
      name: "keepling.reopen_task",
      description: "Reopen exactly one previously-completed task by stable opaque identity."
    }
  ]

  @spec list(map(), map()) :: {:ok, map()}
  def list(_params, _context) do
    tools =
      Enum.map(@implemented_tools, fn %{name: name, description: description} ->
        {:ok, tool_schema} = ToolSchemas.schema(name)
        %{name: name, description: description, inputSchema: tool_schema}
      end)

    {:ok, %{tools: tools}}
  end

  @spec call(map(), map()) :: {:ok, map()} | {:error, map()}
  def call(%{"name" => "keepling.capture_task", "arguments" => arguments}, context)
      when is_map(arguments) do
    dispatch_write(
      "keepling.capture_task",
      arguments,
      context,
      "tasks.write",
      &decode_capture_task/1
    )
  end

  def call(%{"name" => "keepling.update_task", "arguments" => arguments}, context)
      when is_map(arguments) do
    update_task(arguments, context)
  end

  def call(%{"name" => "keepling.complete_task", "arguments" => arguments}, context)
      when is_map(arguments) do
    dispatch_write(
      "keepling.complete_task",
      arguments,
      context,
      "tasks.write",
      &decode_lifecycle(&1, :complete_task)
    )
  end

  def call(%{"name" => "keepling.reopen_task", "arguments" => arguments}, context)
      when is_map(arguments) do
    dispatch_write(
      "keepling.reopen_task",
      arguments,
      context,
      "tasks.write",
      &decode_lifecycle(&1, :reopen_task)
    )
  end

  def call(%{"name" => _unknown_tool}, _context), do: {:error, Errors.invalid_params()}
  def call(_params, _context), do: {:error, Errors.invalid_params()}

  # Shared shape for capture/complete/reopen: adapter-layer scope fast-fail
  # (D-06), the published-schema check, the independent exact-key decode,
  # then dispatch through the SAME Commands.dispatch/3 the HTTP command
  # endpoints use, and map whatever status/body port.execute/3 returns
  # (success OR a domain refusal -- both arrive as {:ok, %{status:, body:}}
  # from the shared port) into the MCP result/error shape. update_task has
  # its own flow below: it needs the task's CURRENT field values to build a
  # correct base_values for the shared narrow-merge command surface (see
  # update_task/2's own moduledoc-style comment).
  defp dispatch_write(tool_name, arguments, context, scope, decode) do
    with :ok <- Scope.require(context, scope),
         :ok <- Keepling.Application.AgentScope.require(context, scope),
         :ok <- ToolSchemas.validate(tool_name, arguments),
         {:ok, command} <- decode.(arguments),
         {:ok, %{status: status, body: body}} <-
           Commands.dispatch(command, dispatch_context(context), CommandStore) do
      render(status, body)
    else
      {:error, :insufficient_scope} -> {:error, Errors.insufficient_scope()}
      {:error, :unknown_tool} -> {:error, Errors.invalid_params()}
      {:error, :invalid_command} -> {:error, Errors.invalid_params()}
      {:error, :infrastructure_failure} -> {:error, Errors.infrastructure_failure()}
    end
  end

  defp render(status, body) when status in 200..299 do
    {:ok, %{content: [%{type: "text", text: Jason.encode!(body)}], structuredContent: body}}
  end

  defp render(status, body), do: {:error, Errors.from_problem(status, body)}

  defp decode_capture_task(params) do
    with true <- Enum.sort(Map.keys(params)) == Enum.sort(@capture_task_keys),
         %{
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "title" => title,
           "version" => 1
         }
         when is_binary(title) <- params,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id) do
      {:ok,
       %{
         mutation_id: mutation_id,
         task_id: task_id,
         title: title,
         type: :capture_task,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_lifecycle(params, type) do
    with true <- Enum.sort(Map.keys(params)) == Enum.sort(@lifecycle_keys),
         %{
           "expected_revision" => expected_revision,
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "version" => 1
         } <- params,
         true <- is_integer(expected_revision) and expected_revision >= 1,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id) do
      {:ok,
       %{
         expected_revision: expected_revision,
         mutation_id: mutation_id,
         task_id: task_id,
         type: type,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  # keepling.update_task addresses exactly one task (D-11's "these four
  # tools address exactly one task"). Its schema deliberately has no
  # `base_values` parameter (unlike the HTTP edit-task/assign-organizations/
  # edit-task-dates endpoints) -- an MCP round trip carries no retained
  # draft to rebase against, so the tool reads the CURRENT task itself,
  # right before dispatch, and uses those current values as base_values.
  # That guarantees the shared narrow three-way merge (Keepling.Domain.Merge)
  # accepts a genuinely new value instead of only accepting a no-op (base ==
  # fields would make the merge require canonical == requested already).
  # `expected_revision` is checked explicitly against the freshly-read
  # revision BEFORE dispatch, using the exact same conflict body shape
  # (code/title/detail/retryable/recovery_action/affected_fields/
  # current_revision) the shared command store's private
  # `semantic_rejection/2` produces for the same {:edit_conflict, _} /
  # {:assignment_conflict, _} domain error the HTTP path returns for the
  # identical situation -- proven equal in `tools_test.exs`. The underlying
  # merge remains the final authority: a genuine race between this read and
  # the transactional write still produces the real domain conflict, mapped
  # through the same `render/2` as every other status/body pair.
  defp update_task(arguments, context) do
    with :ok <- Scope.require(context, "tasks.write"),
         :ok <- Keepling.Application.AgentScope.require(context, "tasks.write"),
         :ok <- ToolSchemas.validate("keepling.update_task", arguments),
         {:ok, task_id, expected_revision, mutation_id, group, fields} <-
           decode_update_task(arguments) do
      # D-13 replay, handled exactly as CommandController.mutation/2 does:
      # a mutation_id already carrying a stored terminal receipt returns
      # THAT result unconditionally -- checked BEFORE the fresh-read/
      # expected_revision gate below, which would otherwise (wrongly)
      # treat a legitimate replay of an since-advanced task as a stale
      # write, because the replay's own expected_revision is, by
      # definition, the value that was current at first delivery, not now.
      case Commands.lookup_result(context, mutation_id, CommandStore) do
        {:ok, %{status: status, body: body}} ->
          render(status, body)

        {:error, :not_found} ->
          dispatch_update(task_id, expected_revision, mutation_id, group, fields, context)

        {:error, :infrastructure_failure} ->
          {:error, Errors.infrastructure_failure()}
      end
    else
      {:error, :insufficient_scope} -> {:error, Errors.insufficient_scope()}
      {:error, :unknown_tool} -> {:error, Errors.invalid_params()}
      {:error, :invalid_command} -> {:error, Errors.invalid_params()}
      {:error, :infrastructure_failure} -> {:error, Errors.infrastructure_failure()}
    end
  end

  defp dispatch_update(task_id, expected_revision, mutation_id, group, fields, context) do
    case Commands.get_task(context, task_id, CommandStore) do
      {:ok, current} ->
        if current["revision"] == expected_revision do
          command =
            build_update_command(group, task_id, expected_revision, mutation_id, fields, current)

          case Commands.dispatch(command, dispatch_context(context), CommandStore) do
            {:ok, %{status: status, body: body}} -> render(status, body)
            {:error, :infrastructure_failure} -> {:error, Errors.infrastructure_failure()}
          end
        else
          {:error,
           Errors.from_problem(409, revision_conflict_body(group, fields, current["revision"]))}
        end

      {:error, :not_found} ->
        {:error, Errors.from_problem(404, task_not_found_body())}

      {:error, :infrastructure_failure} ->
        {:error, Errors.infrastructure_failure()}
    end
  end

  defp decode_update_task(params) do
    with true <-
           Enum.all?(
             Map.keys(params),
             &(&1 in (@update_task_required_keys ++ @update_task_optional_keys))
           ),
         true <- Enum.all?(@update_task_required_keys, &Map.has_key?(params, &1)),
         %{
           "expected_revision" => expected_revision,
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "version" => 1
         } <- params,
         true <- is_integer(expected_revision) and expected_revision >= 1,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id),
         {:ok, group, fields} <- decode_update_group(params) do
      {:ok, task_id, expected_revision, mutation_id, group, fields}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_update_group(params) do
    touched = Map.keys(params) -- @update_task_required_keys

    detail_touched = Enum.filter(touched, &(&1 in ~w(title notes)))
    org_touched = Enum.filter(touched, &(&1 in ~w(project_id tag_ids)))
    date_touched = Enum.filter(touched, &(&1 in ~w(deadline_on planned_on)))

    groups_touched =
      [detail_touched != [], org_touched != [], date_touched != []] |> Enum.count(& &1)

    cond do
      groups_touched != 1 -> {:error, :invalid_command}
      detail_touched != [] -> decode_detail_group(params, detail_touched)
      org_touched != [] -> decode_org_group(params, org_touched)
      true -> decode_date_group(params, date_touched)
    end
  end

  defp decode_detail_group(params, touched) do
    fields = Map.take(params, touched)

    if Enum.all?(fields, fn {_key, value} -> is_binary(value) end) do
      {:ok, :edit_task,
       Map.new(fields, fn {key, value} -> {String.to_existing_atom(key), value} end)}
    else
      {:error, :invalid_command}
    end
  end

  defp decode_org_group(params, touched) do
    with true <- Enum.sort(touched) == ["project_id", "tag_ids"],
         %{"project_id" => project_id, "tag_ids" => tag_ids} <- Map.take(params, touched),
         true <- is_nil(project_id) or is_binary(project_id),
         true <- is_list(tag_ids),
         :ok <- cast_optional_uuid(project_id),
         true <- Enum.all?(tag_ids, &match?({:ok, _uuid}, Ecto.UUID.cast(&1))),
         true <- length(tag_ids) == MapSet.size(MapSet.new(tag_ids)) do
      {:ok, :assign_task_organizations, %{project_id: project_id, tag_ids: Enum.sort(tag_ids)}}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_date_group(params, touched) do
    fields = Map.take(params, touched)

    fields
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, decoded} ->
      case decode_date(value) do
        {:ok, date} -> {:cont, {:ok, Map.put(decoded, String.to_existing_atom(key), date)}}
        :error -> {:halt, {:error, :invalid_command}}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, :edit_task_dates, decoded}
      error -> error
    end
  end

  defp decode_date(nil), do: {:ok, nil}

  defp decode_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp decode_date(_value), do: :error

  defp cast_optional_uuid(nil), do: :ok

  defp cast_optional_uuid(value),
    do: if(match?({:ok, _uuid}, Ecto.UUID.cast(value)), do: :ok, else: :error)

  defp build_update_command(:edit_task, task_id, expected_revision, mutation_id, fields, current) do
    base_values =
      Map.new(fields, fn {key, _value} -> {key, Map.get(current, Atom.to_string(key))} end)

    %{
      base_values: base_values,
      expected_revision: expected_revision,
      fields: fields,
      mutation_id: mutation_id,
      task_id: task_id,
      type: :edit_task,
      version: 1
    }
  end

  defp build_update_command(
         :edit_task_dates,
         task_id,
         expected_revision,
         mutation_id,
         fields,
         current
       ) do
    base_values =
      Map.new(fields, fn {key, _value} ->
        {:ok, value} = decode_date(Map.get(current, Atom.to_string(key)))
        {key, value}
      end)

    %{
      base_values: base_values,
      expected_revision: expected_revision,
      fields: fields,
      mutation_id: mutation_id,
      task_id: task_id,
      type: :edit_task_dates,
      version: 1
    }
  end

  defp build_update_command(
         :assign_task_organizations,
         task_id,
         expected_revision,
         mutation_id,
         fields,
         current
       ) do
    base_values = %{
      project_id: get_in(current, ["project", "id"]),
      tag_ids: (current["tags"] || []) |> Enum.map(& &1["id"]) |> Enum.sort()
    }

    %{
      base_values: base_values,
      expected_revision: expected_revision,
      fields: fields,
      mutation_id: mutation_id,
      task_id: task_id,
      type: :assign_task_organizations,
      version: 1
    }
  end

  # Same literal code/title/detail/retryable/recovery_action strings the
  # shared command store's private `semantic_rejection/2` uses for
  # the matching domain conflict tuple ({:edit_conflict, _} /
  # {:assignment_conflict, _}), so the pre-dispatch expected_revision check
  # above renders a body identical to what the shared merge would itself
  # produce for the same situation -- proven in tools_test.exs.
  defp revision_conflict_body(group, fields, current_revision)
       when group in [:edit_task, :edit_task_dates] do
    %{
      "code" => "task_edit_conflict",
      "detail" => "Review the affected fields before saving again.",
      "recovery_action" => "review_task_conflict",
      "retryable" => false,
      "status" => 409,
      "title" => "Task changed elsewhere",
      "type" => "/problems/task_edit_conflict",
      "affected_fields" => fields |> Map.keys() |> Enum.map(&Atom.to_string/1) |> Enum.sort(),
      "current_revision" => current_revision
    }
  end

  defp revision_conflict_body(:assign_task_organizations, _fields, current_revision) do
    %{
      "code" => "task_assignment_conflict",
      "detail" => "Review the project and tags before saving again.",
      "recovery_action" => "review_task_conflict",
      "retryable" => false,
      "status" => 409,
      "title" => "Task assignments changed elsewhere",
      "type" => "/problems/task_assignment_conflict",
      "affected_fields" => ["project_id", "tag_ids"],
      "current_revision" => current_revision
    }
  end

  defp task_not_found_body do
    %{
      "code" => "task_not_found",
      "detail" => "Refresh the view before trying again.",
      "recovery_action" => "refresh_view",
      "retryable" => false,
      "status" => 404,
      "title" => "Task not found",
      "type" => "/problems/task_not_found"
    }
  end

  # D-24/T-05-01: identity, scope, and client kind are read only from
  # `context` -- assigned by `KeeplingWeb.MCP.Pipeline` from the loaded
  # device grant -- never from the JSON-RPC request body.
  defp dispatch_context(context) do
    %{
      accepted_at: context.accepted_at,
      account_id: context.account_id,
      actor_label: context.actor_label,
      actor_principal: context.actor_principal,
      actor_type: context.actor_type,
      client_kind: context.client_kind
    }
  end
end
