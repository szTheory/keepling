defmodule KeeplingWeb.MCP.Redaction do
  @moduledoc """
  Redaction-by-construction (D-10). Every function here emits a fresh map
  built field by field -- no wholesale struct conversion, no broad
  `Map.take` over a computed key list -- so a field added to an
  underlying domain row never reaches a model until this module names it.

  Source rows arrive from several different shapes: `Commands.get_task/3`'s
  full task body (string keys: id/title/notes/project/tags/revision/
  captured_at/planned_on/deadline_on/completed_at/inbox_state),
  `Keepling.Application.TaskViews`'s bounded-view items (atom keys, a
  narrower field set with no notes/project/tags), and
  `Keepling.Application.Search`'s result items (atom keys, a `completed`
  boolean instead of `inbox_state`). `task/1` tolerates all three: every
  documented key is ALWAYS present in the output (the exact-key-set
  invariant this module exists to prove), but a field the source row does
  not carry is honestly emitted as `nil` rather than fabricated.
  """

  @doc """
  Projects a task-shaped row into the closed resource shape: stable opaque
  identity, title, notes, project identity+name, tag names, the v1 temporal
  fields, a best-effort lifecycle state, and the current revision. Title and
  notes are emitted verbatim -- untrusted user content that must round-trip
  exactly (D-24) -- while every other field is a named, typed projection.
  """
  @spec task(map()) :: map()
  def task(row) when is_map(row) do
    %{
      id: fetch(row, :id),
      title: fetch(row, :title),
      notes: fetch(row, :notes),
      project: task_project(fetch(row, :project)),
      tags: task_tags(fetch(row, :tags)),
      captured_at: fetch(row, :captured_at),
      planned_on: fetch(row, :planned_on),
      deadline_on: fetch(row, :deadline_on),
      completed_at: fetch(row, :completed_at),
      lifecycle_state: lifecycle_state(row),
      revision: fetch(row, :revision)
    }
  end

  @doc """
  Projects a project-shaped row into the closed resource shape: stable
  opaque identity, name, archived flag, task count. No revision, no other
  organization field -- those are not named by this shape.
  """
  @spec project(map()) :: map()
  def project(row) when is_map(row) do
    %{
      id: fetch(row, :id),
      name: project_name(row),
      archived: archived_flag(row),
      task_count: fetch(row, :task_count)
    }
  end

  @doc """
  Wraps a list of already-projected rows with the opaque cursor and a
  boolean indicating whether more pages exist. Nothing else travels in the
  envelope.
  """
  @spec page([map()], String.t() | nil) :: map()
  def page(items, next_cursor) when is_list(items) do
    %{items: items, next_cursor: next_cursor, has_more: not is_nil(next_cursor)}
  end

  # A task's nested project reference carries only identity and name --
  # deliberately narrower than the standalone project resource shape, which
  # also carries archived/task_count. Source is either the
  # `Commands.get_task/3` project reference (`%{"id" => _, "name" => _,
  # "archived" => _}`) or `nil` (no project assigned).
  defp task_project(nil), do: nil

  defp task_project(project) when is_map(project) do
    %{id: fetch(project, :id), name: fetch(project, :name)}
  end

  # "Tag names" -- a list of strings, not tag objects. Writes address tags
  # by opaque id elsewhere (D-15); a read-only tag list needs only the
  # user-visible name.
  defp task_tags(nil), do: []

  defp task_tags(tags) when is_list(tags) do
    Enum.map(tags, &fetch(&1, :name))
  end

  defp project_name(row), do: fetch(row, :name) || fetch(row, :display_name)

  defp archived_flag(row), do: fetch(row, :archived) == true

  # Best-effort lifecycle classification. A row carrying `completed_at` or a
  # `completed` boolean is unambiguously "completed". A row carrying
  # `inbox_state` (the full `Commands.get_task/3` body) uses it verbatim.
  # Absent either -- as with `TaskViews`' Inbox/Today/Upcoming items, which
  # do not select `inbox_state` -- the caller may set `:lifecycle_hint` on
  # the row before calling `task/1` (the view itself sometimes determines
  # the state, e.g. every Inbox-view row IS "inbox"). When none of these
  # are available, the field is honestly emitted as `nil` rather than
  # guessed.
  defp lifecycle_state(row) do
    cond do
      not is_nil(fetch(row, :completed_at)) -> "completed"
      fetch(row, :completed) == true -> "completed"
      is_binary(fetch(row, :inbox_state)) -> fetch(row, :inbox_state)
      is_binary(fetch(row, :lifecycle_hint)) -> fetch(row, :lifecycle_hint)
      true -> nil
    end
  end

  # Tolerates both atom-keyed and string-keyed source rows without ever
  # taking a struct or an unbounded key set wholesale -- every CALLER of
  # this helper names the exact field it wants.
  defp fetch(row, key) when is_map(row) and is_atom(key) do
    cond do
      Map.has_key?(row, key) -> Map.get(row, key)
      Map.has_key?(row, Atom.to_string(key)) -> Map.get(row, Atom.to_string(key))
      true -> nil
    end
  end

  defp fetch(_row, _key), do: nil
end
