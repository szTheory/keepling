defmodule Keepling.Repo.Migrations.ExpandAuthLifecycle do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :label, :text, null: false, default: "Browser"
      add :client_kind, :text, null: false, default: "web"
      add :last_seen_at, :utc_datetime_usec
      add :idle_ttl_seconds, :integer, null: false, default: 2_592_000
      add :absolute_expires_at, :utc_datetime_usec
      add :recent_authenticated_at, :utc_datetime_usec
      add :recent_auth_expires_at, :utc_datetime_usec
    end

    execute(
      """
      UPDATE sessions
      SET last_seen_at = created_at,
          absolute_expires_at = created_at + INTERVAL '180 days',
          recent_authenticated_at = created_at,
          recent_auth_expires_at = created_at + INTERVAL '15 minutes'
      WHERE absolute_expires_at IS NULL
      """,
      "SELECT 1"
    )

    create constraint(:sessions, :sessions_label_length,
             check: "char_length(label) BETWEEN 1 AND 200"
           )

    create constraint(:sessions, :sessions_client_kind,
             check: "client_kind IN ('web', 'electron', 'iphone', 'mcp')"
           )

    create constraint(:sessions, :sessions_expiry_order,
             check:
               "expires_at > created_at AND absolute_expires_at > created_at AND " <>
                 "recent_auth_expires_at >= recent_authenticated_at"
           )

    create constraint(:sessions, :sessions_idle_ttl_positive, check: "idle_ttl_seconds > 0")

    create index(:sessions, [:account_id, :revoked_at, :created_at])

    create table(:account_recovery, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :token_hash, :binary, null: false
      add :issued_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:account_recovery, :account_recovery_expiry_order,
             check: "expires_at > issued_at"
           )

    drop constraint(:account_security_audits, :account_security_audit_closed_type)

    create constraint(:account_security_audits, :account_security_audit_closed_type,
             check:
               "event_type IN (" <>
                 "'timezone_changed', 'login_succeeded', 'login_failed', " <>
                 "'recovery_issued', 'recovery_succeeded', 'reauthenticated', " <>
                 "'session_revoked', 'logout', 'rate_limited')"
           )
  end
end
