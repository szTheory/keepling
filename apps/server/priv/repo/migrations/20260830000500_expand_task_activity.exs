defmodule Keepling.Repo.Migrations.ExpandTaskActivity do
  use Ecto.Migration

  @activity_types ~w(
    task_captured
    task_details_updated
    task_planned
    task_unplanned
    task_clarified
    task_returned_to_inbox
    task_completed
    task_reopened
    task_trashed
    task_restored
    task_undo_applied
  )

  def up do
    alter table(:task_activities) do
      add :actor_principal, :text
      add :actor_label, :text
      add :recovery_state, :text, null: false, default: "not_available"
      add :undone_activity_id, :bigint
    end

    execute("""
    UPDATE task_activities
    SET actor_principal = 'account_owner', actor_label = 'You'
    WHERE actor_type = 'user'
    """)

    execute("ALTER TABLE task_activities ALTER COLUMN actor_principal SET NOT NULL")
    execute("ALTER TABLE task_activities ALTER COLUMN actor_label SET NOT NULL")

    create unique_index(:task_activities, [:account_id, :id],
             name: :task_activities_account_id_id_unique
           )

    execute(
      """
      ALTER TABLE task_activities
      ADD CONSTRAINT task_activities_undone_activity_fk
      FOREIGN KEY (account_id, undone_activity_id)
      REFERENCES task_activities (account_id, id)
      ON DELETE RESTRICT
      """,
      "ALTER TABLE task_activities DROP CONSTRAINT task_activities_undone_activity_fk"
    )

    create constraint(:task_activities, :task_activities_closed_type,
             check: "activity_type IN (#{quoted(@activity_types)})"
           )

    create constraint(:task_activities, :task_activities_version, check: "activity_version = 1")

    create constraint(:task_activities, :task_activities_actor,
             check:
               "((actor_type = 'user' AND actor_principal = 'account_owner') OR " <>
                 "(actor_type = 'agent' AND actor_principal = 'authorized_grant')) AND " <>
                 "char_length(actor_label) BETWEEN 1 AND 200"
           )

    create constraint(:task_activities, :task_activities_client_kind,
             check: "client_kind IN ('web', 'electron', 'iphone', 'mcp')"
           )

    create constraint(:task_activities, :task_activities_recovery_state,
             check:
               "recovery_state IN " <>
                 "('available', 'not_available', 'undone', 'expired', 'stale')"
           )

    create constraint(:task_activities, :task_activities_undo_linkage,
             check:
               "(activity_type = 'task_undo_applied' AND undone_activity_id IS NOT NULL) OR " <>
                 "(activity_type <> 'task_undo_applied' AND undone_activity_id IS NULL)"
           )

    create constraint(:task_activities, :task_activities_exact_revision_delta,
             check:
               "(from_revision IS NULL AND to_revision = 1) OR " <>
                 "(from_revision >= 1 AND to_revision = from_revision + 1)"
           )

    create constraint(:task_activities, :task_activities_changed_fields_object,
             check:
               "jsonb_typeof(changed_fields) = 'object' AND " <>
                 "changed_fields <> '{}'::jsonb"
           )

    drop_if_exists index(:task_activities, [:account_id, :task_id, :accepted_at, :id])

    execute(
      """
      CREATE INDEX task_activities_account_task_keyset_index
      ON task_activities (account_id, task_id, accepted_at DESC, id DESC)
      """,
      "DROP INDEX task_activities_account_task_keyset_index"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS task_activities_account_task_keyset_index")

    create index(:task_activities, [:account_id, :task_id, :accepted_at, :id])

    drop constraint(:task_activities, :task_activities_changed_fields_object)
    drop constraint(:task_activities, :task_activities_exact_revision_delta)
    drop constraint(:task_activities, :task_activities_undo_linkage)
    drop constraint(:task_activities, :task_activities_recovery_state)
    drop constraint(:task_activities, :task_activities_client_kind)
    drop constraint(:task_activities, :task_activities_actor)
    drop constraint(:task_activities, :task_activities_version)
    drop constraint(:task_activities, :task_activities_closed_type)

    execute("ALTER TABLE task_activities DROP CONSTRAINT task_activities_undone_activity_fk")
    drop index(:task_activities, [:account_id, :id], name: :task_activities_account_id_id_unique)

    alter table(:task_activities) do
      remove :undone_activity_id
      remove :recovery_state
      remove :actor_label
      remove :actor_principal
    end
  end

  defp quoted(values), do: values |> Enum.map_join(", ", &"'#{&1}'")
end
