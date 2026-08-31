defmodule Keepling.Application.Commands do
  @moduledoc """
  Shared semantic application boundary used by every outward adapter.
  """

  alias Keepling.Domain.{Organization, Task}

  defmodule Port do
    @moduledoc "Persistence/query port interpreted by an outward adapter."

    @callback execute(map(), map(), function()) :: tuple()
    @callback list_inbox(map()) :: tuple()
    @callback list_organizations(map()) :: tuple()
    @callback lookup_result(map(), String.t()) :: tuple()
  end

  @spec dispatch(map(), map(), module()) :: tuple()
  def dispatch(%{type: :capture_task} = command, context, port) do
    port.execute(command, context, fn accepted_command ->
      Task.capture(%{
        accepted_at: accepted_command.accepted_at,
        task_id: accepted_command.task_id,
        title: accepted_command.title
      })
    end)
  end

  def dispatch(%{type: :edit_task} = command, context, port) do
    port.execute(command, context, fn current_task, accepted_command ->
      Task.edit(current_task, accepted_command)
    end)
  end

  def dispatch(%{type: :clarify_task} = command, context, port) do
    port.execute(command, context, fn current_task, accepted_command ->
      Task.clarify(current_task, accepted_command)
    end)
  end

  def dispatch(%{type: :return_to_inbox} = command, context, port) do
    port.execute(command, context, fn current_task, accepted_command ->
      Task.return_to_inbox(current_task, accepted_command)
    end)
  end

  def dispatch(%{type: :create_organization} = command, context, port) do
    port.execute(command, context, fn accepted_command ->
      Organization.create(accepted_command)
    end)
  end

  def dispatch(%{type: :rename_organization} = command, context, port) do
    port.execute(command, context, fn current_organization, accepted_command ->
      Organization.rename(current_organization, accepted_command)
    end)
  end

  def dispatch(%{type: :archive_organization} = command, context, port) do
    port.execute(command, context, fn current_organization, accepted_command ->
      Organization.archive(current_organization, accepted_command)
    end)
  end

  def dispatch(%{type: :unarchive_organization} = command, context, port) do
    port.execute(command, context, fn current_organization, accepted_command ->
      Organization.unarchive(current_organization, accepted_command)
    end)
  end

  def dispatch(%{type: :assign_task_organizations} = command, context, port) do
    port.execute(command, context, fn current_task, accepted_command ->
      Organization.assign_task(current_task, accepted_command)
    end)
  end

  @spec list_inbox(map(), module()) :: tuple()
  def list_inbox(context, port), do: port.list_inbox(context)

  @spec list_organizations(map(), module()) :: tuple()
  def list_organizations(context, port), do: port.list_organizations(context)

  @spec lookup_result(map(), String.t(), module()) :: tuple()
  def lookup_result(context, mutation_id, port), do: port.lookup_result(context, mutation_id)
end
