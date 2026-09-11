defmodule Keepling.Repo.Migrations.AddExportPerformedAuditEvent do
  use Ecto.Migration

  def up do
    drop constraint(:account_security_audits, :account_security_audit_closed_type)

    create constraint(:account_security_audits, :account_security_audit_closed_type,
             check:
               "event_type IN (" <>
                 "'timezone_changed', 'login_succeeded', 'login_failed', " <>
                 "'recovery_issued', 'recovery_succeeded', 'reauthenticated', " <>
                 "'session_revoked', 'logout', 'rate_limited', " <>
                 "'device_grant_issued', 'device_grant_refreshed', " <>
                 "'device_grant_replay_revoked', 'device_grant_revoked', " <>
                 "'mcp_audience_rejected', 'mcp_client_registered', 'export_performed')"
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
                 "'mcp_audience_rejected', 'mcp_client_registered')"
           )
  end
end
