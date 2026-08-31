defmodule Keepling.Repo.Migrations.AddPersistedConflicts do
  use Ecto.Migration

  def up do
    create table(:persisted_conflicts, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :id, :uuid, primary_key: true
      add :task_id, :uuid, null: false
      add :original_mutation_id, :uuid, null: false
      add :command_type, :text, null: false
      add :expected_revision, :bigint, null: false
      add :latest_revision, :bigint, null: false
      add :affected_fields, {:array, :text}, null: false
      add :base_values, :map, null: false
      add :requested_values, :map, null: false
      add :current_values, :map, null: false
      add :resolved_by_mutation_id, :uuid
      add :resolved_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:persisted_conflicts, [:account_id, :original_mutation_id],
             name: :persisted_conflicts_original_mutation_unique
           )

    create index(:persisted_conflicts, [:account_id, :task_id, :inserted_at, :id],
             name: :persisted_conflicts_task_index
           )

    create constraint(:persisted_conflicts, :persisted_conflicts_revisions_positive,
             check: "expected_revision >= 1 AND latest_revision >= 1"
           )

    create constraint(:persisted_conflicts, :persisted_conflicts_revision_order,
             check: "latest_revision >= expected_revision"
           )

    create constraint(:persisted_conflicts, :persisted_conflicts_closed_command_type,
             check:
               "command_type IN ('edit_task', 'clarify_task', 'complete_task', " <>
                 "'reopen_task', 'trash_task', 'restore_task')"
           )

    create constraint(:persisted_conflicts, :persisted_conflicts_closed_fields,
             check:
               "cardinality(affected_fields) >= 1 AND affected_fields <@ " <>
                 "ARRAY['completed_at', 'notes', 'title', 'trashed_at']::text[]"
           )

    create constraint(:persisted_conflicts, :persisted_conflicts_resolution_complete,
             check:
               "(resolved_by_mutation_id IS NULL AND resolved_at IS NULL) OR " <>
                 "(resolved_by_mutation_id IS NOT NULL AND resolved_at IS NOT NULL)"
           )

    execute(
      """
      ALTER TABLE persisted_conflicts
      ADD CONSTRAINT persisted_conflicts_task_fk
      FOREIGN KEY (account_id, task_id)
      REFERENCES tasks (account_id, id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE persisted_conflicts DROP CONSTRAINT persisted_conflicts_task_fk"
    )

    execute(
      """
      ALTER TABLE persisted_conflicts
      ADD CONSTRAINT persisted_conflicts_original_receipt_fk
      FOREIGN KEY (account_id, original_mutation_id)
      REFERENCES command_receipts (account_id, mutation_id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE persisted_conflicts DROP CONSTRAINT persisted_conflicts_original_receipt_fk"
    )
  end

  def down do
    drop table(:persisted_conflicts)
  end
end
