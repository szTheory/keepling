defmodule Keepling.Repo.Migrations.AddDeviceGrants do
  use Ecto.Migration

  def change do
    create table(:device_grants, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false
      add :installation_id, :text, null: false
      add :label, :text, null: false
      add :client_kind, :text, null: false
      add :redirect_uri, :text, null: false
      add :authorization_code_hash, :binary, null: false
      add :authorization_code_expires_at, :utc_datetime_usec, null: false
      add :authorization_code_consumed_at, :utc_datetime_usec
      add :state_hash, :binary, null: false
      add :pkce_challenge, :text, null: false
      add :access_token_hash, :binary
      add :access_expires_at, :utc_datetime_usec
      add :refresh_inactivity_expires_at, :utc_datetime_usec
      add :family_absolute_expires_at, :utc_datetime_usec, null: false
      add :generation, :bigint, null: false, default: 1
      add :last_refreshed_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:device_grants, [:authorization_code_hash])

    create unique_index(:device_grants, [:access_token_hash],
             where: "access_token_hash IS NOT NULL"
           )

    create index(:device_grants, [:account_id, :installation_id, :inserted_at])

    create constraint(:device_grants, :device_grants_client_kind,
             check: "client_kind IN ('electron', 'iphone')"
           )

    create constraint(:device_grants, :device_grants_generation_positive,
             check: "generation >= 1"
           )

    create constraint(:device_grants, :device_grants_authorization_expiry,
             check: "authorization_code_expires_at > inserted_at"
           )

    create constraint(:device_grants, :device_grants_family_expiry,
             check: "family_absolute_expires_at > inserted_at"
           )

    create table(:device_grant_refresh_tokens) do
      add :grant_id, references(:device_grants, type: :uuid, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :issued_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:device_grant_refresh_tokens, [:token_hash])
    create index(:device_grant_refresh_tokens, [:grant_id, :issued_at])

    create constraint(:device_grant_refresh_tokens, :device_grant_refresh_expiry,
             check: "expires_at > issued_at"
           )

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
  end
end
