defmodule Keepling.Repo.Migrations.AddMcpResourceBinding do
  use Ecto.Migration

  # `resource` is nullable at the DB layer, not required-for-`mcp`: a real
  # HTTP-obtained `mcp` grant always carries it (`KeeplingWeb.
  # DeviceGrantController`'s `@mcp_authorize_keys`/`@mcp_exchange_keys`
  # already require the RFC 8707 `resource` parameter be present and equal
  # to the canonical MCP resource URI, per 05-01-PLAN.md D-33), but a
  # module-level caller that bypasses the controller (as pre-existing
  # `mcp_client_kind_test.exs` does) may still omit it. `KeeplingWeb.MCP.
  # Pipeline`'s audience check treats a stored `NULL` resource the same as
  # any other mismatch: refused, never treated as "no check applies".
  def up do
    alter table(:device_grants) do
      add :resource, :text
    end

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
                 "'device_grant_replay_revoked', 'device_grant_revoked')"
           )

    alter table(:device_grants) do
      remove :resource
    end
  end
end
