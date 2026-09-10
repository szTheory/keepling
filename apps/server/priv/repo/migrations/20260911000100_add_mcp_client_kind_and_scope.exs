defmodule Keepling.Repo.Migrations.AddMcpClientKindAndScope do
  use Ecto.Migration

  def up do
    drop constraint(:device_grants, :device_grants_client_kind)

    create constraint(:device_grants, :device_grants_client_kind,
             check: "client_kind IN ('electron', 'iphone', 'mcp')"
           )

    alter table(:device_grants) do
      add :scope, {:array, :text}, null: false, default: []
    end

    create constraint(:device_grants, :device_grants_scope_closed,
             check:
               "scope <@ ARRAY['tasks.read', 'tasks.write', 'tasks.bulk']::text[] AND " <>
                 "(client_kind = 'mcp' OR array_length(scope, 1) IS NULL)"
           )
  end

  def down do
    drop constraint(:device_grants, :device_grants_scope_closed)

    alter table(:device_grants) do
      remove :scope
    end

    drop constraint(:device_grants, :device_grants_client_kind)

    create constraint(:device_grants, :device_grants_client_kind,
             check: "client_kind IN ('electron', 'iphone')"
           )
  end
end
