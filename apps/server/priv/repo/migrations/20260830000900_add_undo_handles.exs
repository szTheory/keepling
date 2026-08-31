defmodule Keepling.Repo.Migrations.AddUndoHandles do
  use Ecto.Migration

  @command_types ~w(
    edit_task
    clarify_task
    return_to_inbox
    plan_for_today
    unplan_task
    complete_task
    reopen_task
    trash_task
    restore_task
  )
  @inverse_types ~w(details inbox planning completion trash)

  def change do
    create table(:undo_handles, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :id, :uuid, primary_key: true
      add :handle_hash, :binary, null: false
      add :task_id, :uuid, null: false
      add :original_mutation_id, :uuid, null: false
      add :original_activity_id, :bigint, null: false
      add :original_command_type, :text, null: false
      add :produced_revision, :bigint, null: false
      add :inverse_type, :text, null: false
      add :inverse_payload, :map, null: false
      add :label, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :state, :text, null: false, default: "available"
      add :consumed_at, :utc_datetime_usec
      add :result_mutation_id, :uuid
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:undo_handles, [:handle_hash])
    create unique_index(:undo_handles, [:account_id, :original_mutation_id])
    create index(:undo_handles, [:account_id, :task_id, :expires_at])

    create constraint(:undo_handles, :undo_handles_revision_positive,
             check: "produced_revision >= 2"
           )

    create constraint(:undo_handles, :undo_handles_closed_command,
             check: "original_command_type IN (#{quoted(@command_types)})"
           )

    create constraint(:undo_handles, :undo_handles_closed_inverse,
             check: "inverse_type IN (#{quoted(@inverse_types)})"
           )

    create constraint(:undo_handles, :undo_handles_closed_state,
             check: "state IN ('available', 'applied', 'expired', 'stale')"
           )

    create constraint(:undo_handles, :undo_handles_consumption_complete,
             check:
               "(state = 'applied' AND consumed_at IS NOT NULL AND result_mutation_id IS NOT NULL) OR " <>
                 "(state <> 'applied' AND consumed_at IS NULL AND result_mutation_id IS NULL)"
           )

    create constraint(:undo_handles, :undo_handles_inverse_object,
             check: "jsonb_typeof(inverse_payload) = 'object' AND inverse_payload <> '{}'::jsonb"
           )

    execute(
      """
      ALTER TABLE undo_handles
      ADD CONSTRAINT undo_handles_task_fk
      FOREIGN KEY (account_id, task_id)
      REFERENCES tasks (account_id, id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE undo_handles DROP CONSTRAINT undo_handles_task_fk"
    )

    execute(
      """
      ALTER TABLE undo_handles
      ADD CONSTRAINT undo_handles_original_receipt_fk
      FOREIGN KEY (account_id, original_mutation_id)
      REFERENCES command_receipts (account_id, mutation_id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE undo_handles DROP CONSTRAINT undo_handles_original_receipt_fk"
    )

    execute(
      """
      ALTER TABLE undo_handles
      ADD CONSTRAINT undo_handles_original_activity_fk
      FOREIGN KEY (account_id, original_activity_id)
      REFERENCES task_activities (account_id, id)
      ON DELETE RESTRICT
      """,
      "ALTER TABLE undo_handles DROP CONSTRAINT undo_handles_original_activity_fk"
    )
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
