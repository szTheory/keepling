defmodule Keepling.Repo.Migrations.AddOpsState do
  use Ecto.Migration

  def up do
    create table(:operations_state, primary_key: false) do
      add :singleton_key, :boolean, primary_key: true, null: false, default: true
      add :traffic_allowed, :boolean, null: false, default: true
      add :backup_completed_at, :utc_datetime_usec
      add :wal_archived_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:operations_state, :operations_state_singleton_key_true,
             check: "singleton_key = TRUE"
           )

    create table(:restore_verifications) do
      add :source_backup_digest, :binary, null: false
      add :target_recovery_point, :utc_datetime_usec, null: false
      add :verifier_version, :integer, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec, null: false
      add :result_code, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create constraint(:restore_verifications, :restore_verifications_digest_sha256,
             check: "octet_length(source_backup_digest) = 32"
           )

    create constraint(:restore_verifications, :restore_verifications_version_positive,
             check: "verifier_version >= 1"
           )

    create constraint(:restore_verifications, :restore_verifications_ordered,
             check: "target_recovery_point <= finished_at AND started_at <= finished_at"
           )

    create constraint(:restore_verifications, :restore_verifications_closed_result,
             check: "result_code IN ('passed', 'failed')"
           )

    execute("""
    INSERT INTO operations_state (
      singleton_key, traffic_allowed, inserted_at, updated_at
    )
    VALUES (TRUE, TRUE, NOW(), NOW())
    ON CONFLICT (singleton_key) DO NOTHING
    """)
  end

  def down do
    drop table(:restore_verifications)
    drop table(:operations_state)
  end
end
