defmodule KeeplingWeb.MCP.Tools do
  @moduledoc """
  `tools/list` and `tools/call`. Exactly one tool is implemented this plan --
  `keepling.capture_task` -- through the same `Commands.dispatch/3` every
  other adapter calls (D-01/D-02, T-05-01). `tools/list` never advertises a
  tool it cannot execute.
  """

  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias KeeplingWeb.MCP.{Errors, Scope}

  @capture_task_keys ~w(mutation_id task_id title version)

  @capture_task_schema %{
    type: "object",
    additionalProperties: false,
    required: ["mutation_id", "task_id", "title", "version"],
    properties: %{
      mutation_id: %{type: "string", format: "uuid"},
      task_id: %{type: "string", format: "uuid"},
      title: %{type: "string"},
      version: %{const: 1}
    }
  }

  @spec list(map(), map()) :: {:ok, map()}
  def list(_params, _context) do
    {:ok,
     %{
       tools: [
         %{
           name: "keepling.capture_task",
           description: "Capture exactly one new task by stable opaque identity.",
           inputSchema: @capture_task_schema
         }
       ]
     }}
  end

  @spec call(map(), map()) :: {:ok, map()} | {:error, map()}
  def call(%{"name" => "keepling.capture_task", "arguments" => arguments}, context)
      when is_map(arguments) do
    with :ok <- Scope.require(context, "tasks.write"),
         :ok <- Keepling.Application.AgentScope.require(context, "tasks.write"),
         {:ok, command} <- decode_capture_task(arguments),
         {:ok, %{body: body}} <-
           Commands.dispatch(command, dispatch_context(context), CommandStore) do
      {:ok, %{content: [%{type: "text", text: Jason.encode!(body)}], structuredContent: body}}
    else
      {:error, :insufficient_scope} -> {:error, Errors.insufficient_scope()}
      {:error, :invalid_command} -> {:error, Errors.invalid_params()}
      {:error, :infrastructure_failure} -> {:error, Errors.infrastructure_failure()}
    end
  end

  def call(%{"name" => _unknown_tool}, _context), do: {:error, Errors.invalid_params()}
  def call(_params, _context), do: {:error, Errors.invalid_params()}

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
