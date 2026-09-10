defmodule Keepling.Repo.Migrations.AddTaskSearchIndex do
  use Ecto.Migration

  def up do
    execute(
      """
      ALTER TABLE tasks
      ADD COLUMN search_document tsvector
      GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(title, '') || ' ' || coalesce(notes, ''))
      ) STORED
      """,
      "ALTER TABLE tasks DROP COLUMN search_document"
    )

    execute(
      "CREATE INDEX tasks_search_document_gin ON tasks USING GIN (search_document)",
      "DROP INDEX tasks_search_document_gin"
    )
  end

  def down do
    execute(
      "DROP INDEX tasks_search_document_gin",
      "CREATE INDEX tasks_search_document_gin ON tasks USING GIN (search_document)"
    )

    execute(
      "ALTER TABLE tasks DROP COLUMN search_document",
      """
      ALTER TABLE tasks
      ADD COLUMN search_document tsvector
      GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(title, '') || ' ' || coalesce(notes, ''))
      ) STORED
      """
    )
  end
end
