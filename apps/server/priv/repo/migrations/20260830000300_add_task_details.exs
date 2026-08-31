defmodule Keepling.Repo.Migrations.AddTaskDetails do
  use Ecto.Migration

  def up do
    alter table(:tasks) do
      add :notes, :text, null: false, default: ""
    end

    drop constraint(:tasks, :tasks_inbox_state)
    create constraint(:tasks, :tasks_inbox_state, check: "inbox_state IN ('inbox', 'clarified')")

    create constraint(:tasks, :tasks_title_v1_bounds,
             check: "char_length(btrim(title)) BETWEEN 1 AND 512"
           )

    create constraint(:tasks, :tasks_notes_v1_bounds, check: "char_length(notes) <= 50000")
  end

  def down do
    execute("UPDATE tasks SET inbox_state = 'inbox' WHERE inbox_state = 'clarified'")
    drop constraint(:tasks, :tasks_notes_v1_bounds)
    drop constraint(:tasks, :tasks_title_v1_bounds)
    drop constraint(:tasks, :tasks_inbox_state)
    create constraint(:tasks, :tasks_inbox_state, check: "inbox_state = 'inbox'")

    alter table(:tasks) do
      remove :notes
    end
  end
end
