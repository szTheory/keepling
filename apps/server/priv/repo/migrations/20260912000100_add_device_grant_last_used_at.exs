defmodule Keepling.Repo.Migrations.AddDeviceGrantLastUsedAt do
  use Ecto.Migration

  # D-38/T-06-07-03. A nullable `last_used_at` timestamp, kept alongside --
  # never merged with -- `last_refreshed_at` (which advances only on OAuth
  # refresh-token rotation and would narrow the consent-screen claim to "last
  # token refresh" if reused). A newly created grant has a null value here;
  # the write path (Keepling.Adapters.Postgres.CommandStore) advances it only
  # on the event Task 1's checkpoint decided: a first-delivered mutation
  # dispatched under this grant's credential.
  def change do
    alter table(:device_grants) do
      add :last_used_at, :utc_datetime_usec
    end
  end
end
