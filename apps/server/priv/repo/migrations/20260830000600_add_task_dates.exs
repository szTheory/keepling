defmodule Keepling.Repo.Migrations.AddTaskDates do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :planned_on, :date
      add :deadline_on, :date
    end
  end
end
