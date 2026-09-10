defmodule KeeplingWeb.MCP.ToolSchemas do
  @moduledoc """
  Compile-time load of `packages/contracts/generated/mcp-tools.schema.json`
  (D-12, 05-05-PLAN.md Task 2). `@external_resource` forces a recompile
  whenever the generated schema changes, so this module and the contract
  cannot drift silently.

  `validate/2` checks a tool call's arguments against the generated,
  closed schema (required keys present, no key outside the declared
  property set -- the JSON Schema `additionalProperties: false` contract).
  This is the PUBLISHED contract check. Each tool's own
  `Enum.sort(Map.keys(params)) == allowed_keys` decode in
  `KeeplingWeb.MCP.Tools` is the independent ENFORCEMENT check -- both run,
  and a disagreement between them is a test failure, not a runtime
  surprise (Task 2 action text, 05-05-PLAN.md).
  """

  @schema_path Path.join([
                 __DIR__,
                 "..",
                 "..",
                 "..",
                 "..",
                 "..",
                 "packages",
                 "contracts",
                 "generated",
                 "mcp-tools.schema.json"
               ])
               |> Path.expand()

  @external_resource @schema_path

  @schemas @schema_path |> File.read!() |> Jason.decode!()

  @spec tool_names() :: [String.t()]
  def tool_names, do: Map.keys(@schemas)

  @spec schema(String.t()) :: {:ok, map()} | :error
  def schema(tool_name), do: Map.fetch(@schemas, tool_name)

  @spec validate(String.t(), map()) :: :ok | {:error, :unknown_tool | :invalid_command}
  def validate(tool_name, params) when is_map(params) do
    case Map.fetch(@schemas, tool_name) do
      {:ok, tool_schema} -> validate_against(tool_schema, params)
      :error -> {:error, :unknown_tool}
    end
  end

  def validate(_tool_name, _params), do: {:error, :invalid_command}

  defp validate_against(%{"required" => required, "properties" => properties}, params) do
    keys = Map.keys(params)
    declared = Map.keys(properties)

    cond do
      not Enum.all?(required, &(&1 in keys)) -> {:error, :invalid_command}
      not Enum.all?(keys, &(&1 in declared)) -> {:error, :invalid_command}
      true -> :ok
    end
  end
end
