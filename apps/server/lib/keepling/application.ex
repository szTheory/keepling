defmodule Keepling.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Keepling.Repo
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Keepling.Supervisor)
  end
end
