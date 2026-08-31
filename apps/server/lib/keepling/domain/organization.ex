defmodule Keepling.Domain.Organization do
  @moduledoc """
  Pure project, tag, and task-assignment decisions.

  Public identity is the stable opaque ID. Display names remain user-authored
  text while a versioned derived key owns active-name equivalence.
  """

  @name_equivalence_version 1
  @max_name_length 200
  @assignment_fields [:project_id, :tag_ids]

  @enforce_keys [
    :id,
    :kind,
    :display_name,
    :name_key,
    :name_key_version,
    :revision,
    :archived_at
  ]
  defstruct [
    :id,
    :kind,
    :display_name,
    :name_key,
    :name_key_version,
    :revision,
    :archived_at
  ]

  @type kind :: :project | :tag
  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          display_name: String.t(),
          name_key: String.t(),
          name_key_version: 1,
          revision: pos_integer(),
          archived_at: DateTime.t() | nil
        }

  @spec name_equivalence_version() :: 1
  def name_equivalence_version, do: @name_equivalence_version

  @spec normalize_name(term()) ::
          %{display_name: String.t(), key: String.t(), version: 1}
          | {:error, :name_required | :name_too_long}
  def normalize_name(value) when is_binary(value) do
    display_name = value |> String.normalize(:nfc) |> String.trim()

    cond do
      display_name == "" ->
        {:error, :name_required}

      scalar_length(display_name) > @max_name_length ->
        {:error, :name_too_long}

      true ->
        key = display_name |> String.to_charlist() |> :string.casefold() |> List.to_string()

        %{
          display_name: display_name,
          key: key,
          version: @name_equivalence_version
        }
    end
  end

  def normalize_name(_value), do: {:error, :name_required}

  @spec create(map()) :: {:ok, t(), :accepted} | {:error, atom()}
  def create(%{kind: kind} = command) when kind in [:project, :tag] do
    with %{display_name: display_name, key: key, version: version} <-
           normalize_name(command.name) do
      {:ok,
       %__MODULE__{
         id: command.organization_id,
         kind: kind,
         display_name: display_name,
         name_key: key,
         name_key_version: version,
         revision: 1,
         archived_at: nil
       }, :accepted}
    end
  end

  def create(%{kind: _kind}), do: {:error, :invalid_organization_kind}

  @spec rename(t(), map()) :: {:ok, t(), :accepted | :already_satisfied} | {:error, atom()}
  def rename(%__MODULE__{} = organization, command) do
    with :ok <- require_revision(organization, command),
         %{display_name: display_name, key: key, version: version} <-
           normalize_name(command.name) do
      if organization.display_name == display_name do
        {:ok, organization, :already_satisfied}
      else
        {:ok,
         %{
           organization
           | display_name: display_name,
             name_key: key,
             name_key_version: version,
             revision: organization.revision + 1
         }, :accepted}
      end
    end
  end

  @spec archive(t(), map()) ::
          {:ok, t(), :accepted | :already_satisfied}
          | {:error, :stale_organization | {:project_archive_blocked, non_neg_integer()}}
  def archive(%__MODULE__{} = organization, command) do
    with :ok <- require_revision(organization, command) do
      cond do
        organization.archived_at != nil ->
          {:ok, organization, :already_satisfied}

        organization.kind == :project and command.active_unfinished_task_count > 0 ->
          {:error, {:project_archive_blocked, command.active_unfinished_task_count}}

        true ->
          {:ok,
           %{
             organization
             | archived_at: command.accepted_at,
               revision: organization.revision + 1
           }, :accepted}
      end
    end
  end

  @spec unarchive(t(), map()) ::
          {:ok, t(), :accepted | :already_satisfied}
          | {:error, :stale_organization | :active_name_collision}
  def unarchive(%__MODULE__{} = organization, command) do
    with :ok <- require_revision(organization, command) do
      cond do
        organization.archived_at == nil ->
          {:ok, organization, :already_satisfied}

        command.active_name_collision? ->
          {:error, :active_name_collision}

        true ->
          {:ok, %{organization | archived_at: nil, revision: organization.revision + 1},
           :accepted}
      end
    end
  end

  @spec assign_task(map(), map()) ::
          {:ok, map(), map() | nil, :accepted | :already_satisfied}
          | {:error, atom() | {:assignment_conflict, [String.t()]}}
  def assign_task(current, command) when is_map(current) do
    with :ok <- require_assignment_revision(current, command),
         {:ok, base_values} <- normalize_assignment(command.base_values),
         {:ok, fields} <- normalize_assignment(command.fields),
         {:ok, updated, changes} <- merge_assignment(current, base_values, fields) do
      if map_size(changes) == 0 do
        {:ok, current, nil, :already_satisfied}
      else
        updated = %{updated | revision: current.revision + 1}

        activity = %{
          type: :task_details_updated,
          version: 1,
          from_revision: current.revision,
          to_revision: updated.revision,
          accepted_at: command.accepted_at,
          changed_fields: changes
        }

        {:ok, updated, activity, :accepted}
      end
    end
  end

  defp require_revision(organization, %{expected_revision: expected_revision}) do
    if organization.revision == expected_revision, do: :ok, else: {:error, :stale_organization}
  end

  defp require_revision(_organization, _command), do: :ok

  defp require_assignment_revision(current, %{expected_revision: expected_revision})
       when is_integer(expected_revision) and expected_revision >= 1 and
              expected_revision <= current.revision,
       do: :ok

  defp require_assignment_revision(_current, _command), do: {:error, :invalid_expected_revision}

  defp normalize_assignment(%{project_id: project_id, tag_ids: tag_ids})
       when (is_nil(project_id) or is_binary(project_id)) and is_list(tag_ids) do
    if Enum.all?(tag_ids, &is_binary/1) and length(tag_ids) == MapSet.size(MapSet.new(tag_ids)) do
      {:ok, %{project_id: project_id, tag_ids: Enum.sort(tag_ids)}}
    else
      {:error, :invalid_assignment}
    end
  end

  defp normalize_assignment(_assignment), do: {:error, :invalid_assignment}

  defp merge_assignment(current, base_values, fields) do
    conflicts =
      @assignment_fields
      |> Enum.reject(fn field ->
        current_value = Map.fetch!(current, field)

        current_value == Map.fetch!(base_values, field) or
          current_value == Map.fetch!(fields, field)
      end)
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    if conflicts == [] do
      {updated, changes} =
        Enum.reduce(@assignment_fields, {current, %{}}, fn field, {task, changed} ->
          current_value = Map.fetch!(task, field)
          requested_value = Map.fetch!(fields, field)

          if current_value == requested_value do
            {task, changed}
          else
            {
              Map.put(task, field, requested_value),
              Map.put(changed, Atom.to_string(field), %{
                "from" => current_value,
                "to" => requested_value
              })
            }
          end
        end)

      {:ok, updated, changes}
    else
      {:error, {:assignment_conflict, conflicts}}
    end
  end

  defp scalar_length(value), do: value |> String.codepoints() |> length()
end
