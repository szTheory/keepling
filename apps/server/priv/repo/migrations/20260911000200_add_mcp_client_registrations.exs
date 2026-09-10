defmodule Keepling.Repo.Migrations.AddMcpClientRegistrations do
  use Ecto.Migration

  def up do
    create table(:mcp_client_registrations, primary_key: false) do
      add :client_id, :text, primary_key: true
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false
      add :client_name, :text, null: false
      add :redirect_uris, {:array, :text}, null: false
      add :created_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
    end

    create index(:mcp_client_registrations, [:account_id])

    create constraint(:mcp_client_registrations, :mcp_client_registrations_name_length,
             check: "char_length(client_name) BETWEEN 1 AND 200"
           )

    create constraint(:mcp_client_registrations, :mcp_client_registrations_redirect_uris_bounded,
             check: "array_length(redirect_uris, 1) BETWEEN 1 AND 5"
           )

    drop constraint(:account_security_audits, :account_security_audit_closed_type)

    create constraint(:account_security_audits, :account_security_audit_closed_type,
             check:
               "event_type IN (" <>
                 "'timezone_changed', 'login_succeeded', 'login_failed', " <>
                 "'recovery_issued', 'recovery_succeeded', 'reauthenticated', " <>
                 "'session_revoked', 'logout', 'rate_limited', " <>
                 "'device_grant_issued', 'device_grant_refreshed', " <>
                 "'device_grant_replay_revoked', 'device_grant_revoked', " <>
                 "'mcp_audience_rejected', 'mcp_client_registered')"
           )
  end

  def down do
    drop constraint(:account_security_audits, :account_security_audit_closed_type)

    create constraint(:account_security_audits, :account_security_audit_closed_type,
             check:
               "event_type IN (" <>
                 "'timezone_changed', 'login_succeeded', 'login_failed', " <>
                 "'recovery_issued', 'recovery_succeeded', 'reauthenticated', " <>
                 "'session_revoked', 'logout', 'rate_limited', " <>
                 "'device_grant_issued', 'device_grant_refreshed', " <>
                 "'device_grant_replay_revoked', 'device_grant_revoked', " <>
                 "'mcp_audience_rejected')"
           )

    drop table(:mcp_client_registrations)
  end
end
