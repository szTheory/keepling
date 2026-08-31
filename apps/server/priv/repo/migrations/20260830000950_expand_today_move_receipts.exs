defmodule Keepling.Repo.Migrations.ExpandTodayMoveReceipts do
  use Ecto.Migration

  def change do
    alter table(:today_order_receipts) do
      add :task_id, :uuid
    end

    create index(:today_order_receipts, [:account_id, :task_id])
  end
end
