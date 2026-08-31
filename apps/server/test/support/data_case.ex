defmodule Keepling.DataCase do
  @moduledoc """
  ExUnit case support for tests that own a SQL Sandbox connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Keepling.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Keepling.DataCase
    end
  end

  setup tags do
    Keepling.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Starts a Sandbox owner whose lifetime is bound to the current test.
  """
  def setup_sandbox(tags) do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Keepling.Repo, shared: not tags[:async])
    ExUnit.Callbacks.on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  @doc """
  Converts changeset errors into a map of interpolated messages.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
