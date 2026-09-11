defmodule Keepling.Application.Export do
  @moduledoc """
  Inward, storage-neutral export bundle writer (06-04-PLAN.md Task 3).

  No dependency on Phoenix transport, MCP, generated clients, or client
  persistence -- this module only knows how to turn already-queried entity
  rows into the published bundle shape, never how those rows were read.
  `Keepling.Adapters.Postgres.Export` owns the transactional, streaming
  Postgres reads and calls into `write_bundle/4` with the results.

  Bundle write order is the correctness property this module exists to
  enforce: every `data/*.ndjson` file, `tasks.md`, and `FORMAT.md` are
  written first; `manifest.json` is written LAST. If the writer is
  interrupted after an entity file and before the manifest, the staging
  directory has no `manifest.json` and therefore cannot validate as a
  bundle (T-06-04-04).
  """

  @format_md_path Path.expand(
                    "../../../../../packages/contracts/schemas/export/FORMAT.md",
                    __DIR__
                  )
  @external_resource @format_md_path
  @format_md File.read!(@format_md_path)

  @entities ~w(task project tag task-activity conflict today-order account-settings access-inventory)

  @doc "The closed, ordered list of entity names this bundle always writes, one NDJSON file each."
  @spec entities() :: [String.t()]
  def entities, do: @entities

  @doc """
  Writes a complete export bundle into `destination_dir` and returns the zip
  path plus the exact manifest file list.

  `entity_streams` must contain one `Enumerable.t()` per name in
  `entities/0`, each yielding plain string-keyed maps already in the
  entity's canonical (ascending stable id, or feed sequence) order --
  ordering is the caller's responsibility, never re-derived here.
  `manifest_extra` supplies the fields this module cannot know on its own:
  `"feed_high_water_sequence"` and `"restore_epoch"`.
  """
  @spec write_bundle(String.t(), String.t(), %{String.t() => Enumerable.t()}, map()) ::
          {:ok, %{bundle_path: String.t(), files: [map()], manifest: map()}}
  def write_bundle(account_id, destination_dir, entity_streams, manifest_extra)
      when is_binary(account_id) and is_binary(destination_dir) and is_map(entity_streams) and
             is_map(manifest_extra) do
    staging_dir = Path.join(destination_dir, "#{account_id}-export-staging")
    data_dir = Path.join(staging_dir, "data")
    File.mkdir_p!(data_dir)

    {entity_files, task_lines} = write_entities!(data_dir, entity_streams)

    tasks_md_entry = write_tasks_md!(staging_dir, task_lines)
    format_md_entry = write_format_md!(staging_dir)

    files = entity_files ++ [tasks_md_entry, format_md_entry]

    manifest =
      Map.merge(
        %{
          "export_format_version" => 1,
          "keepling_version" => keepling_version(),
          "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "account_id" => account_id,
          "files" => files
        },
        manifest_extra
      )

    write_manifest!(staging_dir, manifest)

    bundle_path = Path.join(destination_dir, "#{account_id}-export.zip")
    zip_directory!(staging_dir, bundle_path)
    File.chmod!(bundle_path, 0o600)
    File.rm_rf!(staging_dir)

    {:ok, %{bundle_path: bundle_path, files: files, manifest: manifest}}
  end

  # Writes every entity's data/<entity>.ndjson in the fixed order entities/0
  # declares, one open/close per file so an empty stream still produces an
  # empty (present) file rather than a missing one. While writing the
  # "task" entity specifically, also accumulates the rendered tasks.md
  # lines -- a single pass over the task stream, since Enumerable streams
  # are consumed once.
  defp write_entities!(data_dir, entity_streams) do
    Enum.map_reduce(@entities, [], fn entity, task_lines_acc ->
      stream = Map.fetch!(entity_streams, entity)
      path = Path.join(data_dir, "#{entity}.ndjson")
      on_row = if entity == "task", do: &task_markdown_line/1, else: fn _row -> nil end

      {row_count, digest, collected_lines} = write_ndjson!(path, stream, on_row)

      entry = %{
        "path" => "data/#{entity}.ndjson",
        "sha256" => digest,
        "rowCount" => row_count
      }

      next_acc = if entity == "task", do: collected_lines, else: task_lines_acc
      {entry, next_acc}
    end)
  end

  defp write_ndjson!(path, stream, on_row) do
    device = File.open!(path, [:write, :utf8])

    {count, digest_state, lines} =
      Enum.reduce(stream, {0, :crypto.hash_init(:sha256), []}, fn row, {count, digest, lines} ->
        line = canonical_json(row) <> "\n"
        IO.write(device, line)

        collected =
          case on_row.(row) do
            nil -> lines
            rendered -> [rendered | lines]
          end

        {count + 1, :crypto.hash_update(digest, line), collected}
      end)

    File.close(device)

    {count, :crypto.hash_final(digest_state) |> Base.encode16(case: :lower), Enum.reverse(lines)}
  end

  defp write_tasks_md!(staging_dir, task_lines) do
    path = Path.join(staging_dir, "tasks.md")
    content = render_tasks_md(task_lines)
    File.write!(path, content)
    file_entry("tasks.md", path, length(task_lines))
  end

  defp write_format_md!(staging_dir) do
    path = Path.join(staging_dir, "FORMAT.md")
    File.write!(path, @format_md)
    line_count = @format_md |> String.split("\n") |> length()
    file_entry("FORMAT.md", path, line_count)
  end

  defp write_manifest!(staging_dir, manifest) do
    path = Path.join(staging_dir, "manifest.json")
    File.write!(path, canonical_json(manifest))
  end

  defp file_entry(name, path, row_count) do
    digest =
      path
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{"path" => name, "sha256" => digest, "rowCount" => row_count}
  end

  defp render_tasks_md(task_lines) do
    header = "# Tasks\n\n"

    if task_lines == [] do
      header <> "_No tasks._\n"
    else
      header <> Enum.join(task_lines, "\n") <> "\n"
    end
  end

  defp task_markdown_line(%{"title" => title} = row) do
    checkbox = if row["completed_at"], do: "[x]", else: "[ ]"
    trashed = if row["trashed_at"], do: " (trashed)", else: ""
    "- #{checkbox} #{title}#{trashed}"
  end

  defp zip_directory!(staging_dir, bundle_path) do
    files =
      staging_dir
      |> relative_files()
      |> Enum.sort()
      |> Enum.map(&String.to_charlist/1)

    {:ok, _created} =
      :zip.create(String.to_charlist(bundle_path), files, cwd: String.to_charlist(staging_dir))
  end

  defp relative_files(staging_dir) do
    staging_dir
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, staging_dir))
  end

  defp keepling_version do
    case Application.spec(:keepling, :vsn) do
      nil -> "unknown"
      vsn -> List.to_string(vsn)
    end
  end

  # Canonical (sorted) JSON key order, applied recursively -- FORMAT.md's
  # own encoding contract. Explicit rather than relying on Erlang's flat-map
  # iteration order, so this holds regardless of map size or representation.
  @spec canonical_json(term()) :: String.t()
  def canonical_json(value), do: value |> canonicalize() |> Jason.encode!()

  defp canonicalize(%Jason.OrderedObject{} = value), do: value

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> {to_string(k), canonicalize(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value), do: value
end
