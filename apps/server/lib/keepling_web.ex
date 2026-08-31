defmodule KeeplingWeb do
  @moduledoc """
  Defines the outward Phoenix transport boundary.

  Keep quoted definitions short and delegate product behavior to semantic
  application commands. Transport modules may depend inward; domain and
  application modules must never depend on this namespace.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: KeeplingWeb.Endpoint,
        router: KeeplingWeb.Router,
        statics: KeeplingWeb.static_paths()
    end
  end

  @doc """
  Dispatches to the requested Phoenix boundary definition.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
