defmodule Keepling.Repo.Migrations.CreateCoreTaskCommandTables do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :singleton_key, :boolean, null: false, default: true
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:accounts, [:singleton_key])
    create constraint(:accounts, :accounts_singleton_key_true, check: "singleton_key = TRUE")

    create table(:sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false
      add :credential_hash, :binary, null: false
      add :created_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:sessions, [:credential_hash])
    create index(:sessions, [:account_id, :expires_at])

    create table(:tasks, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :id, :uuid, primary_key: true
      add :title, :text, null: false
      add :inbox_state, :text, null: false
      add :revision, :bigint, null: false
      add :captured_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:tasks, :tasks_inbox_state, check: "inbox_state = 'inbox'")
    create constraint(:tasks, :tasks_revision_positive, check: "revision >= 1")
    create index(:tasks, [:account_id, :inbox_state, :captured_at, :id])

    create table(:command_receipts, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :mutation_id, :uuid, primary_key: true
      add :fingerprint, :binary, null: false
      add :terminal, :boolean, null: false, default: false
      add :response_status, :integer
      add :response, :map
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:command_receipts, :terminal_response_complete,
             check:
               "(terminal = FALSE AND response_status IS NULL AND response IS NULL) OR " <>
                 "(terminal = TRUE AND response_status IS NOT NULL AND response IS NOT NULL)"
           )

    create table(:task_activities) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false
      add :task_id, :uuid, null: false
      add :mutation_id, :uuid, null: false
      add :activity_type, :text, null: false
      add :activity_version, :integer, null: false
      add :actor_type, :text, null: false
      add :client_kind, :text, null: false
      add :from_revision, :bigint
      add :to_revision, :bigint, null: false
      add :changed_fields, :map, null: false
      add :accepted_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:task_activities, [:account_id, :mutation_id])

    create index(:task_activities, [:account_id, :task_id, :accepted_at, :id])

    create constraint(:task_activities, :task_activities_revision_positive,
             check: "to_revision >= 1"
           )

    execute(
      """
      ALTER TABLE task_activities
      ADD CONSTRAINT task_activities_task_fk
      FOREIGN KEY (account_id, task_id)
      REFERENCES tasks (account_id, id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE task_activities DROP CONSTRAINT task_activities_task_fk"
    )

    execute(
      """
      ALTER TABLE task_activities
      ADD CONSTRAINT task_activities_receipt_fk
      FOREIGN KEY (account_id, mutation_id)
      REFERENCES command_receipts (account_id, mutation_id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE task_activities DROP CONSTRAINT task_activities_receipt_fk"
    )
  end
end
