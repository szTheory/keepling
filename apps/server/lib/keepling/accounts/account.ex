defmodule Keepling.Accounts.Account do
  @moduledoc """
  Persistence representation for Keepling's sole personal account.

  Wire DTOs, task-domain values, and this Ecto schema remain separate values.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "accounts" do
    field :singleton_key, :boolean, default: true
    field :password_hash, :string, redact: true
    field :timezone, :string
    field :today_view_revision, :integer, default: 1
    field :upcoming_view_revision, :integer, default: 1
    field :activity_view_revision, :integer, default: 1

    timestamps(type: :utc_datetime_usec)
  end

  def creation_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:password_hash, :timezone])
    |> validate_required([:password_hash, :timezone])
    |> unique_constraint(:singleton_key)
  end

  def timezone_changeset(%__MODULE__{} = account, timezone) do
    account
    |> change(timezone: timezone)
    |> validate_required([:timezone])
  end
end
