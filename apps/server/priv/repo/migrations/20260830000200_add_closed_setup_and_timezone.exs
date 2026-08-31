defmodule Keepling.Repo.Migrations.AddClosedSetupAndTimezone do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :password_hash, :text
      add :timezone, :text
      add :today_view_revision, :bigint, null: false, default: 1
      add :upcoming_view_revision, :bigint, null: false, default: 1
      add :activity_view_revision, :bigint, null: false, default: 1
    end

    create constraint(:accounts, :accounts_timezone_nonempty,
             check: "timezone IS NULL OR length(timezone) > 0"
           )

    create constraint(:accounts, :accounts_view_revisions_positive,
             check:
               "today_view_revision >= 1 AND upcoming_view_revision >= 1 AND " <>
                 "activity_view_revision >= 1"
           )

    create table(:account_setup, primary_key: false) do
      add :singleton_key, :boolean, primary_key: true, null: false, default: true
      add :token_hash, :binary
      add :issued_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :consumed_at, :utc_datetime_usec
      add :disabled_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:account_setup, :account_setup_singleton_key_true,
             check: "singleton_key = TRUE"
           )

    create constraint(:account_setup, :account_setup_token_lifecycle,
             check:
               "(token_hash IS NULL AND issued_at IS NULL AND expires_at IS NULL) OR " <>
                 "(token_hash IS NOT NULL AND issued_at IS NOT NULL AND expires_at > issued_at)"
           )

    create constraint(:account_setup, :account_setup_disabled_is_consumed,
             check: "disabled_at IS NULL OR consumed_at IS NOT NULL"
           )

    create table(:account_security_audits) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false
      add :event_type, :text, null: false
      add :event_version, :integer, null: false
      add :accepted_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:account_security_audits, [:account_id, :accepted_at, :id])

    create constraint(:account_security_audits, :account_security_audit_closed_type,
             check: "event_type IN ('timezone_changed')"
           )

    create constraint(:account_security_audits, :account_security_audit_version,
             check: "event_version = 1"
           )
  end
end
