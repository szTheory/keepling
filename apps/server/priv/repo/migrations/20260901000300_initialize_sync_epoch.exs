defmodule Keepling.Repo.Migrations.InitializeSyncEpoch do
  use Ecto.Migration

  def up do
    epoch = Ecto.UUID.generate()

    execute("""
    INSERT INTO sync_epochs (singleton_key, epoch, finalized, inserted_at, updated_at)
    VALUES (TRUE, '#{epoch}', TRUE, NOW(), NOW())
    ON CONFLICT (singleton_key) DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM sync_epochs WHERE singleton_key = TRUE")
  end
end
