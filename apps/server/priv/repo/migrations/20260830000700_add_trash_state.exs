defmodule Keepling.Repo.Migrations.AddTrashState do
  use Ecto.Migration

  def up do
    alter table(:accounts) do
      add :trash_view_revision, :bigint, null: false, default: 1
    end

    drop constraint(:accounts, :accounts_task_view_revisions_positive)

    create constraint(:accounts, :accounts_task_view_revisions_positive,
             check:
               "inbox_view_revision >= 1 AND completed_view_revision >= 1 AND " <>
                 "today_order_revision >= 1 AND trash_view_revision >= 1"
           )

    alter table(:tasks) do
      add :trashed_at, :utc_datetime_usec
    end

    create index(:tasks, [:account_id, :trashed_at, :id], name: :tasks_trash_keyset)
  end

  def down do
    drop index(:tasks, [:account_id, :trashed_at, :id], name: :tasks_trash_keyset)

    alter table(:tasks) do
      remove :trashed_at
    end

    drop constraint(:accounts, :accounts_task_view_revisions_positive)

    create constraint(:accounts, :accounts_task_view_revisions_positive,
             check:
               "inbox_view_revision >= 1 AND completed_view_revision >= 1 AND " <>
                 "today_order_revision >= 1"
           )

    alter table(:accounts) do
      remove :trash_view_revision
    end
  end
end
