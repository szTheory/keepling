defmodule Keepling.Application.Ops do
  @moduledoc """
  Inward operational policy shared by health, source, and release adapters.

  Results are closed, JSON-compatible, privacy-bounded envelopes. Shell, Mix,
  release, and Phoenix callers may parse or render them, but may not decide
  recovery, compatibility, deployment, or target-safety policy themselves.
  """

  @verbs ~w(preflight status doctor backup restore restore-verify deploy upgrade replace-host)
  @destructive ~w(restore restore-verify deploy upgrade replace-host)
  @exit_codes %{
    ok: 0,
    usage: 2,
    refusal: 10,
    dependency: 20,
    compatibility: 30,
    recovery: 40,
    execution: 50
  }
  @digest ~r/^sha256:[0-9a-f]{64}$/

  defmodule Port do
    @moduledoc "Outward port for bounded inspection and admitted operational execution."

    @callback inspect(map() | keyword()) :: {:ok, map()} | {:error, atom()}
    @callback execute(String.t(), map(), map() | keyword()) ::
                :ok | {:ok, map()} | {:error, atom()}
  end

  @spec verbs() :: [String.t()]
  def verbs, do: @verbs

  @spec exit_code(atom()) :: non_neg_integer()
  def exit_code(class), do: Map.fetch!(@exit_codes, class)

  @spec run(String.t(), map(), module(), map() | keyword()) :: map()
  def run(operation, input, port, options)
      when operation in @verbs and is_map(input) and is_atom(port) do
    case port.inspect(options) do
      {:ok, inspection} when is_map(inspection) ->
        decide(operation, input, inspection, port, options)

      {:error, reason} when is_atom(reason) ->
        dependency_failure(operation, reason)

      _unknown ->
        failure(operation, "inspection_failed", :execution, false, [], %{})
    end
  rescue
    _error -> dependency_failure(operation, :database_unavailable)
  end

  def run(operation, _input, _port, _options) do
    failure(
      if(is_binary(operation), do: operation, else: "unknown"),
      "invalid_operation",
      :usage,
      false,
      ["Use `keepling ops --help` to list the closed command vocabulary."],
      %{}
    )
  end

  @doc "Returns process-only public liveness without touching the port."
  @spec liveness() :: map()
  def liveness, do: %{"status" => "alive"}

  @doc "Returns minimal public readiness; backup and WAL freshness are deliberately excluded."
  @spec readiness(module(), map() | keyword()) :: map()
  def readiness(port, options) do
    case port.inspect(options) do
      {:ok, inspection} when is_map(inspection) -> readiness_result(inspection)
      _ -> %{"code" => "database_unavailable", "status" => "not_ready"}
    end
  rescue
    _error -> %{"code" => "database_unavailable", "status" => "not_ready"}
  end

  defp decide("status", _input, inspection, _port, _options),
    do: status_result("status", inspection)

  defp decide("doctor", _input, inspection, _port, _options),
    do: status_result("doctor", inspection)

  defp decide("preflight", _input, inspection, _port, _options) do
    case blocking_condition(inspection, include_backup?: true) do
      nil -> success("preflight", "preflight_passed", bounded_facts(inspection))
      condition -> condition_result("preflight", condition, inspection)
    end
  end

  defp decide(operation, input, inspection, port, options) when operation in @destructive do
    with :ok <- validate_destructive_input(operation, input),
         nil <-
           blocking_condition(inspection,
             include_backup?: operation in ~w(deploy upgrade replace-host)
           ),
         :ok <- execute(port, operation, input, options) do
      success(operation, operation <> "_completed", bounded_facts(inspection))
    else
      {:error, :invalid_target} -> unsafe_target(operation)
      {:error, reason} when is_atom(reason) -> execution_failure(operation, reason)
      condition when is_atom(condition) -> condition_result(operation, condition, inspection)
    end
  end

  defp decide("backup" = operation, input, inspection, port, options) do
    case execute(port, operation, input, options) do
      :ok -> success(operation, "backup_completed", bounded_facts(inspection))
      {:error, reason} -> execution_failure(operation, reason)
    end
  end

  defp execute(port, operation, input, options) do
    case port.execute(operation, input, options) do
      :ok -> :ok
      {:ok, result} when is_map(result) -> :ok
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :execution_failed}
    end
  end

  defp validate_destructive_input(operation, input)
       when operation in ~w(restore restore-verify) do
    required = ~w(confirmed source_digest target_class)

    if Enum.sort(Map.keys(input)) == required and input["confirmed"] == true and
         input["target_class"] == "empty_isolated" and
         is_binary(input["source_digest"]) and Regex.match?(@digest, input["source_digest"]) do
      :ok
    else
      {:error, :invalid_target}
    end
  end

  defp validate_destructive_input(operation, input)
       when operation in ~w(deploy upgrade replace-host) do
    required = ~w(confirmed target_class tested_oci_digest)

    if Enum.sort(Map.keys(input)) == required and input["confirmed"] == true and
         input["target_class"] == "replaceable_candidate" and
         is_binary(input["tested_oci_digest"]) and
         Regex.match?(@digest, input["tested_oci_digest"]) do
      :ok
    else
      {:error, :invalid_target}
    end
  end

  defp status_result(operation, inspection) do
    case blocking_condition(inspection, include_backup?: true) do
      nil ->
        success(operation, operation <> "_healthy", bounded_facts(inspection))

      :backup_rpo_not_met ->
        failure(
          operation,
          "backup_rpo_not_met",
          :dependency,
          true,
          ["Run `keepling ops backup --json` and inspect archive health."],
          bounded_facts(inspection),
          "degraded"
        )

      condition ->
        condition_result(operation, condition, inspection)
    end
  end

  defp blocking_condition(inspection, options) do
    include_backup? = Keyword.fetch!(options, :include_backup?)

    cond do
      get_in(inspection, ["database"]) != "available" ->
        :database_unavailable

      get_in(inspection, ["migrations", "state"]) != "finalized" ->
        :migrations_pending

      get_in(inspection, ["migrations", "pending_count"]) != 0 ->
        :migrations_pending

      get_in(inspection, ["restore_epoch"]) != "finalized" ->
        :restore_epoch_unfinalized

      get_in(inspection, ["traffic"]) != "accepting" ->
        :traffic_disabled

      not valid_schema?(inspection) ->
        :schema_incompatible

      not valid_protocol?(inspection) ->
        :protocol_incompatible

      include_backup? and
          (get_in(inspection, ["backup", "state"]) != "current" or
             get_in(inspection, ["wal", "state"]) != "current") ->
        :backup_rpo_not_met

      true ->
        nil
    end
  end

  defp readiness_result(inspection) do
    case blocking_condition(inspection, include_backup?: false) do
      nil -> %{"code" => "ready", "status" => "ready"}
      condition -> %{"code" => Atom.to_string(condition), "status" => "not_ready"}
    end
  end

  defp valid_schema?(inspection) do
    case inspection["schema"] do
      %{"current" => current, "minimum" => minimum, "maximum" => maximum}
      when is_integer(current) and is_integer(minimum) and is_integer(maximum) ->
        current >= minimum and current <= maximum

      _ ->
        false
    end
  end

  defp valid_protocol?(inspection) do
    case inspection["protocol_range"] do
      %{"minimum" => minimum, "maximum" => maximum}
      when is_integer(minimum) and is_integer(maximum) ->
        minimum >= 1 and minimum <= maximum

      _ ->
        false
    end
  end

  defp condition_result(operation, :backup_rpo_not_met, inspection) do
    failure(
      operation,
      operation <> "_backup_rpo_not_met",
      :refusal,
      true,
      ["Create and verify a current backup before retrying."],
      bounded_facts(inspection),
      "refused"
    )
  end

  defp condition_result(operation, condition, inspection) do
    {class, remediation} = condition_details(condition)

    failure(
      operation,
      Atom.to_string(condition),
      class,
      condition in [:database_unavailable, :migrations_pending],
      [remediation],
      bounded_facts(inspection)
    )
  end

  defp condition_details(:database_unavailable),
    do: {:dependency, "Check PostgreSQL connectivity and retry the command."}

  defp condition_details(:migrations_pending),
    do: {:compatibility, "Apply the pending expand-compatible migrations before retrying."}

  defp condition_details(:schema_incompatible),
    do: {:compatibility, "Use an image whose declared schema range includes the current schema."}

  defp condition_details(:protocol_incompatible),
    do:
      {:compatibility, "Use an image whose declared protocol range overlaps the supported train."}

  defp condition_details(:restore_epoch_unfinalized),
    do: {:recovery, "Complete restore verification and finalize the synchronization epoch."}

  defp condition_details(:traffic_disabled),
    do: {:recovery, "Finish the active maintenance or recovery step before accepting traffic."}

  defp dependency_failure(operation, _reason) do
    failure(
      operation,
      "database_unavailable",
      :dependency,
      true,
      ["Check PostgreSQL connectivity and retry the command."],
      %{"database" => "unavailable"}
    )
  end

  defp unsafe_target(operation) do
    failure(
      operation,
      operation <> "_unsafe_target",
      :refusal,
      false,
      ["Use an explicit empty isolated target and an immutable SHA-256 source or image digest."],
      %{},
      "refused"
    )
  end

  defp execution_failure(operation, _reason) do
    failure(
      operation,
      operation <> "_adapter_unavailable",
      :execution,
      true,
      ["Configure the required outward operations adapter and retry."],
      %{}
    )
  end

  defp success(operation, code, facts) do
    result(operation, "ok", code, :ok, false, [], facts)
  end

  defp failure(operation, code, class, retryable, remediation, facts, status \\ "failed") do
    result(operation, status, code, class, retryable, remediation, facts)
  end

  defp result(operation, status, code, class, retryable, remediation, facts) do
    %{
      "version" => 1,
      "operation" => operation,
      "status" => status,
      "code" => code,
      "exit_code" => exit_code(class),
      "retryable" => retryable,
      "facts" => facts,
      "remediation" => remediation
    }
  end

  defp bounded_facts(inspection) do
    Map.take(inspection, [
      "backup",
      "database",
      "last_restore_verification",
      "migrations",
      "protocol_range",
      "release_revision",
      "restore_epoch",
      "schema",
      "tested_oci_digest",
      "traffic",
      "wal"
    ])
  end
end
