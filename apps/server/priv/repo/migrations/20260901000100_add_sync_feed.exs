defmodule Keepling.Repo.Migrations.AddSyncFeed do
  use Ecto.Migration

  def up do
    create table(:sync_accounts, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :high_sequence, :bigint, null: false, default: 0
      add :low_water_sequence, :bigint, null: false, default: 0
      add :low_water_ordinal, :integer, null: false, default: -1
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:sync_accounts, :sync_accounts_positions_nonnegative,
             check:
               "high_sequence >= 0 AND low_water_sequence >= 0 AND " <>
                 "low_water_ordinal >= -1 AND low_water_sequence <= high_sequence"
           )

    create table(:sync_epochs, primary_key: false) do
      add :singleton_key, :boolean, primary_key: true, null: false, default: true
      add :epoch, :uuid, null: false
      add :finalized, :boolean, null: false, default: true
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:sync_epochs, :sync_epochs_singleton_key_true,
             check: "singleton_key = TRUE"
           )

    create table(:sync_changes, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :sequence, :bigint, primary_key: true
      add :ordinal, :integer, primary_key: true
      add :mutation_id, :uuid, null: false
      add :kind, :text, null: false
      add :entity_type, :text
      add :entity_id, :uuid
      add :entity_revision, :bigint
      add :payload, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:sync_changes, [:account_id, :sequence, :ordinal],
             name: :sync_changes_position_unique
           )

    create index(:sync_changes, [:account_id, :entity_type, :entity_id, :sequence, :ordinal],
             name: :sync_changes_entity_index
           )

    create constraint(:sync_changes, :sync_changes_position_positive,
             check: "sequence >= 1 AND ordinal >= 0"
           )

    create constraint(:sync_changes, :sync_changes_entity_revision_positive,
             check: "entity_revision IS NULL OR entity_revision >= 1"
           )

    create constraint(:sync_changes, :sync_changes_closed_kind,
             check:
               "kind IN ('command_outcome', 'task_snapshot', 'organization_snapshot', " <>
                 "'conflict_snapshot', 'collection_tombstone', 'undo_metadata')"
           )

    execute(
      """
      ALTER TABLE sync_changes
      ADD CONSTRAINT sync_changes_receipt_fk
      FOREIGN KEY (account_id, mutation_id)
      REFERENCES command_receipts (account_id, mutation_id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE sync_changes DROP CONSTRAINT sync_changes_receipt_fk"
    )
  end

  def down do
    drop table(:sync_changes)
    drop table(:sync_epochs)
    drop table(:sync_accounts)
  end
end
