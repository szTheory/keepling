defmodule Keepling.Release do
  @moduledoc """
  Release-safe entry points that start only Ecto and the repository.

  This module owns argument parsing and rendering shared with the source Mix
  task. Operational decisions remain in `Keepling.Application.Ops`.
  """

  alias Keepling.Adapters.Postgres.OpsStore
  alias Keepling.Application.Ops
  alias Keepling.Repo

  @switches [
    json: :boolean,
    color: :boolean,
    timeout_ms: :integer,
    confirmed: :boolean,
    source_digest: :string,
    target_class: :string,
    tested_oci_digest: :string
  ]
  @common ~w(color json timeout_ms)a
  @operation_switches %{
    "preflight" => [],
    "status" => [],
    "doctor" => [],
    "backup" => [],
    "restore" => ~w(confirmed source_digest target_class)a,
    "restore-verify" => ~w(confirmed source_digest target_class)a,
    "deploy" => ~w(confirmed target_class tested_oci_digest)a,
    "upgrade" => ~w(confirmed target_class tested_oci_digest)a,
    "replace-host" => ~w(confirmed target_class tested_oci_digest)a
  }

  @spec invoke([String.t()]) :: {String.t(), non_neg_integer()}
  def invoke(args) when is_list(args) do
    previous_level = Logger.level()
    Logger.configure(level: :emergency)

    try do
      do_invoke(args)
    after
      Logger.flush()
      Logger.configure(level: previous_level)
    end
  end

  defp do_invoke(args) do
    with {:ok, parsed} <- parse(args),
         :ok <- Application.ensure_loaded(:keepling),
         {:ok, result, _started_apps} <-
           Ecto.Migrator.with_repo(
             Repo,
             fn _repo ->
               Ops.run(parsed.operation, parsed.input, OpsStore, %{
                 timeout_ms: parsed.timeout_ms
               })
             end,
             mode: :temporary
           ) do
      {render(result, parsed.format), result["exit_code"]}
    else
      {:error, %{operation: operation, format: format}} ->
        result = Ops.invalid_result(operation)
        {render(result, format), result["exit_code"]}

      _error ->
        result = dependency_result(args)
        {render(result, requested_format(args)), result["exit_code"]}
    end
  end

  @doc "Prints one result and exits with its stable result class."
  @spec ops([String.t()]) :: no_return()
  def ops(args \\ System.argv()) do
    {output, exit_code} = invoke(args)
    IO.puts(output)
    System.halt(exit_code)
  end

  @doc "Decodes the shell wrapper's base64-per-argument release transport."
  @spec ops_from_env() :: no_return()
  def ops_from_env do
    args =
      System.get_env("KEEPLING_OPS_ARGS_BASE64", "")
      |> String.split(":", trim: true)
      |> Enum.map(fn encoded ->
        case Base.decode64(encoded) do
          {:ok, argument} -> argument
          :error -> "invalid-encoded-argument"
        end
      end)

    ops(args)
  end

  @spec render(map(), :human | :json) :: String.t()
  def render(result, :json), do: Jason.encode!(result)

  def render(result, :human) do
    headline =
      "#{result["operation"]}: #{result["code"]} (exit #{result["exit_code"]})"

    remediation =
      Enum.map(result["remediation"], fn step -> "remediation: " <> step end)

    Enum.join([headline | remediation], "\n")
  end

  defp parse(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)
    operation = List.first(positional) || "unknown"
    format = if Keyword.get(options, :json, false), do: :json, else: :human
    keys = Keyword.keys(options)
    allowed = @common ++ Map.get(@operation_switches, operation, [])

    valid? =
      positional == [operation] and operation in Ops.verbs() and invalid == [] and
        Enum.uniq(keys) == keys and Enum.all?(keys, &(&1 in allowed)) and
        valid_timeout?(Keyword.get(options, :timeout_ms, 1_000))

    if valid? do
      {:ok,
       %{
         operation: operation,
         input: operation_input(operation, options),
         timeout_ms: Keyword.get(options, :timeout_ms, 1_000),
         format: format
       }}
    else
      {:error, %{operation: operation, format: format}}
    end
  end

  defp operation_input(operation, options) do
    @operation_switches
    |> Map.fetch!(operation)
    |> Map.new(fn key -> {Atom.to_string(key), Keyword.get(options, key)} end)
  end

  defp valid_timeout?(timeout), do: is_integer(timeout) and timeout >= 1 and timeout <= 5_000

  defp dependency_result(args) do
    operation =
      case args do
        [candidate | _] -> if(candidate in Ops.verbs(), do: candidate, else: "unknown")
        _ -> "unknown"
      end

    Ops.run(operation, %{}, UnavailablePort, %{})
  end

  defp requested_format(args), do: if("--json" in args, do: :json, else: :human)

  defmodule UnavailablePort do
    @moduledoc false
    @behaviour Keepling.Application.Ops.Port

    @impl true
    def inspect(_options), do: {:error, :database_unavailable}

    @impl true
    def execute(_operation, _input, _options), do: {:error, :database_unavailable}
  end
end
