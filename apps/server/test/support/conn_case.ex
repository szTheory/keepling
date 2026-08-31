defmodule KeeplingWeb.ConnCase do
  @moduledoc """
  ExUnit case support for Endpoint requests with SQL Sandbox ownership.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint KeeplingWeb.Endpoint

      use KeeplingWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import KeeplingWeb.ConnCase
    end
  end

  setup tags do
    Keepling.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
