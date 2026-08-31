defmodule Keepling.Repo do
  use Ecto.Repo,
    otp_app: :keepling,
    adapter: Ecto.Adapters.Postgres
end
