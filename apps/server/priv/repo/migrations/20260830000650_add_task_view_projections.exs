defmodule Keepling.Repo.Migrations.AddTaskViewProjections do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :inbox_view_revision, :bigint, null: false, default: 1
      add :completed_view_revision, :bigint, null: false, default: 1
      add :today_order_revision, :bigint, null: false, default: 1
    end

    create constraint(:accounts, :accounts_task_view_revisions_positive,
             check:
               "inbox_view_revision >= 1 AND completed_view_revision >= 1 AND " <>
                 "today_order_revision >= 1"
           )

    alter table(:tasks) do
      add :completed_at, :utc_datetime_usec
    end

    create index(:tasks, [:account_id, :inbox_state, :completed_at, :captured_at, :id],
             name: :tasks_inbox_keyset
           )

    create index(:tasks, [:account_id, :completed_at, :id], name: :tasks_completed_keyset)

    create index(:tasks, [:account_id, :planned_on, :deadline_on, :captured_at, :id],
             name: :tasks_temporal_keyset
           )

    create table(:today_task_order, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :task_id, :uuid, primary_key: true
      add :section, :text, null: false
      add :position, :integer, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:today_task_order, :today_task_order_section,
             check: "section IN ('overdue', 'today')"
           )

    create constraint(:today_task_order, :today_task_order_position_positive,
             check: "position >= 1"
           )

    create unique_index(:today_task_order, [:account_id, :section, :position])

    execute(
      """
      ALTER TABLE today_task_order
      ADD CONSTRAINT today_task_order_task_fk
      FOREIGN KEY (account_id, task_id)
      REFERENCES tasks (account_id, id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE today_task_order DROP CONSTRAINT today_task_order_task_fk"
    )
  end
end
