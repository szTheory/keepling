defmodule Keepling.Repo.Migrations.AddAuditorRole do
  use Ecto.Migration

  # D-45/T-06-12-01 (06-12-PLAN.md Task 1). Provisions the read-only database
  # identity the trust-soak oracle (tooling/trust-lanes/oracle.mjs) uses for
  # its independent server-side read. A checker that shares the application's
  # own write-capable role would make "the oracle can never write" a promise
  # kept only by convention, not by grant. `keepling_auditor` holds SELECT on
  # every table in the public schema (present and future, via an ALTER
  # DEFAULT PRIVILEGES clause) and nothing else -- no session role has any
  # write privilege unless explicitly granted, so omitting every other grant
  # is sufficient; nothing here needs to be explicitly revoked.
  #
  # The password is read from KEEPLING_AUDITOR_PASSWORD at migration-apply
  # time so it never sits in the migration source. A stable, documented
  # fallback (KEEPLING_AUDITOR_PASSWORD unset in dev/test only) keeps a fresh
  # dev/test database usable without a first-run secret-provisioning step;
  # production deploys are expected to set the real environment variable.
  #
  # `DO $$ ... $$` guards make role creation idempotent (Postgres has no
  # `CREATE ROLE IF NOT EXISTS`), matching the round-trip contract every
  # other migration in this project already provides.
  def up do
    password = System.get_env("KEEPLING_AUDITOR_PASSWORD") || "keepling_auditor_dev_only"
    escaped_password = String.replace(password, "'", "''")

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'keepling_auditor') THEN
        EXECUTE format('CREATE ROLE keepling_auditor LOGIN PASSWORD %L', '#{escaped_password}');
      ELSE
        EXECUTE format('ALTER ROLE keepling_auditor PASSWORD %L', '#{escaped_password}');
      END IF;
    END
    $$;
    """)

    # GRANT CONNECT ON DATABASE takes an identifier, not a function call, so
    # the target database name is resolved dynamically inside a DO block
    # rather than assumed or hardcoded from application config.
    execute("""
    DO $$
    BEGIN
      EXECUTE format('GRANT CONNECT ON DATABASE %I TO keepling_auditor', current_database());
    END
    $$;
    """)
    execute("GRANT USAGE ON SCHEMA public TO keepling_auditor")
    execute("GRANT SELECT ON ALL TABLES IN SCHEMA public TO keepling_auditor")
    execute(
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO keepling_auditor"
    )
  end

  def down do
    execute(
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM keepling_auditor"
    )
    execute("REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM keepling_auditor")
    execute("REVOKE USAGE ON SCHEMA public FROM keepling_auditor")
    execute("""
    DO $$
    BEGIN
      EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM keepling_auditor', current_database());
    END
    $$;
    """)
    execute("DROP ROLE IF EXISTS keepling_auditor")
  end
end
