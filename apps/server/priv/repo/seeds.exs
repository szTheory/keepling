# Keepling does not create an account from deployment seeds or a first request.
# This deterministic record exists only in the isolated Playwright database;
# Plan 01-06 owns production operator-token setup and sole-account creation.
if Mix.env() == :test and System.get_env("KEEPLING_E2E_SEED") == "phase-1" do
  now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

  Ecto.Adapters.SQL.query!(
    Keepling.Repo,
    """
    INSERT INTO accounts (id, singleton_key, inserted_at, updated_at)
    VALUES ($1, TRUE, $2, $2)
    ON CONFLICT (id) DO NOTHING
    """,
    [Ecto.UUID.dump!("00000000-0000-4000-8000-000000000001"), now]
  )
end

:ok
