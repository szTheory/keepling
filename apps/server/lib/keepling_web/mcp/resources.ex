defmodule KeeplingWeb.MCP.Resources do
  @moduledoc """
  `resources/list` and `resources/read` for the seven MCP-01 read surfaces
  (D-08): the four bounded task views, a single task, the project list, and
  a single project's tasks. Every read routes through the SAME
  `Keepling.Application.{TaskViews, Search, Projects, Commands}` queries
  the HTTP API and every other adapter call (D-09) -- this module adds no
  new query, no new Postgres access, and projects every result through
  `KeeplingWeb.MCP.Redaction` before it ever reaches a model (D-10).

  Every read checks `tasks.read` twice: once at the adapter fast-fail
  (`KeeplingWeb.MCP.Scope`) and once again at the application boundary
  (`Keepling.Application.AgentScope`) -- the same two-layer gate every MCP
  write tool already uses (T-05-19).
  """

  alias Keepling.Application.{AgentScope, Commands, Projects, Search, TaskViews}
  alias KeeplingWeb.MCP.{Errors, Redaction, Scope}

  @default_limit 20
  @maximum_limit 50

  # Config-injected ports (config/config.exs) rather than a local alias of
  # the concrete Postgres adapter -- this module names no adapter directly;
  # every read still goes through the Application-layer query above, only
  # the port implementation is resolved from config.
  @task_views_port Application.compile_env!(:keepling, :mcp_task_views_port)
  @projects_port Application.compile_env!(:keepling, :mcp_projects_port)
  @command_store_port Application.compile_env!(:keepling, :mcp_command_store_port)
  @search_port Application.compile_env!(:keepling, :mcp_search_port)

  @view_uris %{
    "keepling://tasks/inbox" => :inbox,
    "keepling://tasks/today" => :today,
    "keepling://tasks/upcoming" => :upcoming,
    "keepling://tasks/completed" => :completed
  }

  @resource_list [
    %{
      uri: "keepling://tasks/inbox",
      name: "Inbox",
      description: "Uncategorized captured tasks awaiting clarification.",
      mimeType: "application/json"
    },
    %{
      uri: "keepling://tasks/today",
      name: "Today",
      description: "Tasks planned or due today, in Today order.",
      mimeType: "application/json"
    },
    %{
      uri: "keepling://tasks/upcoming",
      name: "Upcoming",
      description: "Tasks planned or due in the future, grouped by date.",
      mimeType: "application/json"
    },
    %{
      uri: "keepling://tasks/completed",
      name: "Completed",
      description: "Completed tasks, most recent first.",
      mimeType: "application/json"
    },
    %{
      uri: "keepling://tasks/{task_id}",
      name: "Task",
      description: "One task by its stable opaque identity.",
      mimeType: "application/json"
    },
    %{
      uri: "keepling://projects",
      name: "Projects",
      description: "Active (non-archived) projects with task counts.",
      mimeType: "application/json"
    },
    %{
      uri: "keepling://projects/{project_id}",
      name: "Project tasks",
      description: "One project's tasks, bounded and paginated.",
      mimeType: "application/json"
    }
  ]

  @spec list(map(), map()) :: {:ok, map()} | {:error, map()}
  def list(_params, context) do
    with :ok <- Scope.require(context, "tasks.read"),
         :ok <- AgentScope.require(context, "tasks.read") do
      {:ok, %{resources: @resource_list}}
    else
      {:error, :insufficient_scope} -> {:error, Errors.insufficient_scope()}
    end
  end

  @spec read(map(), map()) :: {:ok, map()} | {:error, map()}
  def read(%{"uri" => uri} = params, context) when is_binary(uri) do
    with :ok <- Scope.require(context, "tasks.read"),
         :ok <- AgentScope.require(context, "tasks.read"),
         {:ok, limit} <- limit(params) do
      dispatch_read(uri, Map.get(params, "cursor"), limit, context)
    else
      {:error, :insufficient_scope} -> {:error, Errors.insufficient_scope()}
      {:error, :invalid_limit} -> {:error, Errors.invalid_params()}
    end
  end

  def read(_params, _context), do: {:error, Errors.invalid_params()}

  @doc """
  D-08's parameterized search read. Called from `KeeplingWeb.MCP.Tools`'s
  `keepling.search_tasks` tool -- the tool call is registered in `Tools`
  (it takes arguments, so it is a tool, not a resource), but the actual
  read routes through the SAME shared `Keepling.Application.Search.query/4`
  the HTTP `GET /api/v1/search` endpoint calls (D-09), and is projected
  through `KeeplingWeb.MCP.Redaction` exactly like every other read here.
  Checks `tasks.read` at both layers independently, same as `list/2` and
  `read/2` above.
  """
  @spec search(map(), String.t(), map()) :: {:ok, map()} | {:error, map()}
  def search(context, term, options) do
    with :ok <- Scope.require(context, "tasks.read"),
         :ok <- AgentScope.require(context, "tasks.read") do
      case Search.query(search_context(context), term, options, @search_port) do
        {:ok, page} ->
          items = Enum.map(page.items, &Redaction.task/1)
          {:ok, Redaction.page(items, page.next_cursor)}

        {:error, :invalid_cursor} ->
          {:error, Errors.invalid_params()}

        {:error, :infrastructure_failure} ->
          {:error, Errors.infrastructure_failure()}
      end
    else
      {:error, :insufficient_scope} -> {:error, Errors.insufficient_scope()}
    end
  end

  defp dispatch_read(uri, cursor, limit, context) when is_map_key(@view_uris, uri) do
    read_view(Map.fetch!(@view_uris, uri), cursor, limit, context)
  end

  defp dispatch_read("keepling://projects", cursor, limit, context) do
    read_projects(cursor, limit, context)
  end

  defp dispatch_read("keepling://projects/" <> project_id, cursor, limit, context)
       when project_id != "" do
    read_project_tasks(project_id, cursor, limit, context)
  end

  defp dispatch_read("keepling://tasks/" <> task_id, _cursor, _limit, context)
       when task_id != "" do
    read_task(task_id, context)
  end

  defp dispatch_read(_uri, _cursor, _limit, _context), do: {:error, Errors.invalid_params()}

  defp read_view(view, cursor, limit, context) do
    ctx = task_view_context(context)
    options = %{cursor: cursor, limit: limit}

    case TaskViews.list(view, ctx, options, @task_views_port) do
      {:ok, page} ->
        items =
          page.items
          |> Enum.map(&Map.put(&1, :lifecycle_hint, view_lifecycle_hint(view)))
          |> Enum.map(&Redaction.task/1)

        render_resource(view_uri(view), items, page.next_cursor)

      error ->
        map_read_error(error)
    end
  end

  defp read_projects(cursor, limit, context) do
    ctx = projects_context(context)
    options = %{cursor: cursor, limit: limit}

    case Projects.list(ctx, options, @projects_port) do
      {:ok, page} ->
        items = Enum.map(page.items, &Redaction.project/1)
        render_resource("keepling://projects", items, page.next_cursor)

      error ->
        map_read_error(error)
    end
  end

  defp read_project_tasks(project_id, cursor, limit, context) do
    ctx = projects_context(context)
    options = %{cursor: cursor, limit: limit}

    case Ecto.UUID.cast(project_id) do
      {:ok, _uuid} ->
        case Projects.tasks(ctx, project_id, options, @projects_port) do
          {:ok, page} ->
            items = Enum.map(page.items, &Redaction.task/1)
            render_resource("keepling://projects/#{project_id}", items, page.next_cursor)

          {:error, :not_found} ->
            # No "project not found" member exists in the closed MCP error
            # vocabulary; `task_not_found` is the closest existing member
            # ("identity not found, refresh before retrying") and avoids
            # widening the closed vocabulary for one resource path.
            {:error, Errors.task_not_found()}

          error ->
            map_read_error(error)
        end

      :error ->
        {:error, Errors.task_not_found()}
    end
  end

  defp read_task(task_id, context) do
    case Ecto.UUID.cast(task_id) do
      {:ok, _uuid} ->
        case Commands.get_task(%{account_id: context.account_id}, task_id, @command_store_port) do
          {:ok, task} ->
            render_resource("keepling://tasks/#{task_id}", [Redaction.task(task)], nil)

          {:error, :not_found} ->
            {:error, Errors.task_not_found()}

          {:error, :infrastructure_failure} ->
            {:error, Errors.infrastructure_failure()}
        end

      # A malformed identity collapses to the SAME not-found error as a
      # well-formed but foreign one (T-05-20) -- identity existence is
      # never probeable by the shape of the error returned.
      :error ->
        {:error, Errors.task_not_found()}
    end
  end

  defp render_resource(uri, items, next_cursor) do
    payload = Redaction.page(items, next_cursor)
    {:ok, %{contents: [%{uri: uri, mimeType: "application/json", text: Jason.encode!(payload)}]}}
  end

  defp map_read_error({:error, :invalid_cursor}), do: {:error, Errors.invalid_params()}
  defp map_read_error({:error, :invalid_limit}), do: {:error, Errors.invalid_params()}
  # A stale keyset cursor (the underlying view changed shape between pages)
  # collapses to the same closed `invalid_params` member as any other bad
  # argument -- there is no dedicated "view changed" member in the closed
  # MCP vocabulary, and inventing one is out of this plan's scope.
  defp map_read_error({:error, :stale_cursor}), do: {:error, Errors.invalid_params()}
  defp map_read_error({:error, :not_found}), do: {:error, Errors.infrastructure_failure()}
  defp map_read_error({:error, :infrastructure_failure}), do: {:error, Errors.infrastructure_failure()}

  defp view_uri(:inbox), do: "keepling://tasks/inbox"
  defp view_uri(:today), do: "keepling://tasks/today"
  defp view_uri(:upcoming), do: "keepling://tasks/upcoming"
  defp view_uri(:completed), do: "keepling://tasks/completed"

  # Only Inbox and Completed are unambiguous from the view alone -- Today
  # and Upcoming can each contain a mix of inbox/clarified tasks, which
  # `TaskViews`' own item shape does not disclose without a further query
  # this plan does not add.
  defp view_lifecycle_hint(:inbox), do: "inbox"
  defp view_lifecycle_hint(:completed), do: "completed"
  defp view_lifecycle_hint(_other), do: nil

  defp limit(params) do
    case Map.get(params, "limit") do
      nil -> {:ok, @default_limit}
      limit when is_integer(limit) and limit >= 1 and limit <= @maximum_limit -> {:ok, limit}
      limit when is_integer(limit) and limit > @maximum_limit -> {:ok, @maximum_limit}
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp task_view_context(context) do
    %{
      account_id: context.account_id,
      accepted_at: context.accepted_at,
      cursor_secret: cursor_secret("keepling-task-view-cursor-v1")
    }
  end

  defp projects_context(context) do
    %{account_id: context.account_id, cursor_secret: cursor_secret("keepling-projects-cursor-v1")}
  end

  defp search_context(context) do
    %{account_id: context.account_id, cursor_secret: cursor_secret("keepling-search-cursor-v1")}
  end

  defp cursor_secret(salt) do
    endpoint_config = Application.fetch_env!(:keepling, KeeplingWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_config, :secret_key_base)
    :crypto.mac(:hmac, :sha256, secret_key_base, salt)
  end
end
