defmodule KeeplingWeb.Router do
  use KeeplingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
  end

  pipeline :authenticated do
    plug KeeplingWeb.Auth, :load_session
    plug KeeplingWeb.Auth, :require_authenticated
    plug :protect_from_forgery
  end

  pipeline :mutation do
    plug KeeplingWeb.Auth, :require_trusted_origin
  end

  pipeline :recent_auth do
    plug KeeplingWeb.Auth, :require_recent_auth
  end

  pipeline :test_fixture do
    plug KeeplingWeb.Auth, :require_test_fixture
    plug :protect_from_forgery
  end

  if Mix.env() == :test do
    scope "/api/v1/test", KeeplingWeb do
      pipe_through [:api, :test_fixture]

      post "/session", CommandController, :test_session
    end
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api]

    post "/setup", AuthController, :setup
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api, :mutation]

    post "/login", AuthController, :login
    post "/recovery", AuthController, :recovery
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api, :authenticated]

    get "/session", CommandController, :session
    get "/sessions", AuthController, :sessions
    get "/inbox", CommandController, :inbox
    get "/mutations/:mutation_id", CommandController, :mutation
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api, :authenticated, :mutation]

    post "/commands/capture-task", CommandController, :capture_task
    post "/reauthenticate", AuthController, :reauthenticate
    post "/logout", AuthController, :logout
    patch "/sessions/:id", AuthController, :update_session
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api, :authenticated, :mutation, :recent_auth]

    delete "/sessions/:id", AuthController, :revoke_session
  end
end
