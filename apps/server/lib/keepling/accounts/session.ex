defmodule Keepling.Accounts.Session do
  @moduledoc """
  Persistence representation for one revocable browser or future device session.

  The raw session credential is deliberately absent from this schema. Only its
  SHA-256 hash and closed lifecycle metadata are stored in PostgreSQL.
  """

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "sessions" do
    field :credential_hash, :binary, redact: true
    field :label, :string
    field :client_kind, :string
    field :created_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :absolute_expires_at, :utc_datetime_usec
    field :recent_authenticated_at, :utc_datetime_usec
    field :recent_auth_expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :account, Keepling.Accounts.Account

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Keepling.Accounts.GrantPort do
  @moduledoc """
  Compatibility seam for later external-user-agent and scoped grant adapters.

  Phase 1 does not implement native or MCP grants. Keeping the closed callback
  shapes here prevents later clients from copying browser cookies or passwords.
  """

  @type authorization_code_request :: %{
          required(:code) => String.t(),
          required(:code_verifier) => String.t(),
          required(:redirect_uri) => String.t(),
          required(:client_kind) => :electron | :iphone
        }

  @type scoped_grant_request :: %{
          required(:scopes) => [atom()],
          required(:client_kind) => :mcp
        }

  @callback exchange_authorization_code(authorization_code_request()) ::
              {:ok, map()} | {:error, atom()}
  @callback issue_scoped_grant(scoped_grant_request()) :: {:ok, map()} | {:error, atom()}
end
