defmodule Keepling.Repo.Migrations.AddOrganizations do
  use Ecto.Migration

  def up do
    create table(:organizations, primary_key: false) do
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :id, :uuid, primary_key: true
      add :kind, :text, null: false
      add :display_name, :text, null: false
      add :name_key, :text, null: false
      add :name_key_version, :integer, null: false, default: 1
      add :archived_at, :utc_datetime_usec
      add :revision, :integer, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:organizations, :organizations_kind, check: "kind IN ('project', 'tag')")

    create constraint(:organizations, :organizations_name_v1_bounds,
             check:
               "name_key_version = 1 AND char_length(display_name) BETWEEN 1 AND 200 AND char_length(name_key) >= 1"
           )

    create constraint(:organizations, :organizations_revision_positive, check: "revision >= 1")
    create unique_index(:organizations, [:account_id, :id, :kind])

    execute(
      """
      CREATE UNIQUE INDEX organizations_active_name_unique
      ON organizations (account_id, kind, name_key_version, name_key)
      WHERE archived_at IS NULL
      """,
      "DROP INDEX organizations_active_name_unique"
    )

    alter table(:tasks) do
      add :project_id, :uuid
      add :project_kind, :text, null: false, default: "project"
    end

    create constraint(:tasks, :tasks_project_kind, check: "project_kind = 'project'")

    execute(
      """
      ALTER TABLE tasks
      ADD CONSTRAINT tasks_project_fk
      FOREIGN KEY (account_id, project_id, project_kind)
      REFERENCES organizations (account_id, id, kind)
      """,
      "ALTER TABLE tasks DROP CONSTRAINT tasks_project_fk"
    )

    create table(:task_tags, primary_key: false) do
      add :account_id, :uuid, primary_key: true
      add :task_id, :uuid, primary_key: true
      add :tag_id, :uuid, primary_key: true
      add :tag_kind, :text, null: false, default: "tag"
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create constraint(:task_tags, :task_tags_kind, check: "tag_kind = 'tag'")

    execute(
      """
      ALTER TABLE task_tags
      ADD CONSTRAINT task_tags_task_fk
      FOREIGN KEY (account_id, task_id)
      REFERENCES tasks (account_id, id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE task_tags DROP CONSTRAINT task_tags_task_fk"
    )

    execute(
      """
      ALTER TABLE task_tags
      ADD CONSTRAINT task_tags_organization_fk
      FOREIGN KEY (account_id, tag_id, tag_kind)
      REFERENCES organizations (account_id, id, kind)
      """,
      "ALTER TABLE task_tags DROP CONSTRAINT task_tags_organization_fk"
    )

    create index(:task_tags, [:account_id, :tag_id, :task_id])
    create index(:tasks, [:account_id, :project_id, :id])
  end

  def down do
    drop table(:task_tags)

    execute("ALTER TABLE tasks DROP CONSTRAINT tasks_project_fk")
    drop constraint(:tasks, :tasks_project_kind)

    alter table(:tasks) do
      remove :project_kind
      remove :project_id
    end

    drop table(:organizations)
  end
end
