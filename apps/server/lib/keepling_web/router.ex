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
    get "/views/inbox", TaskViewController, :inbox
    get "/today", TaskViewController, :today
    get "/upcoming", TaskViewController, :upcoming
    get "/completed", TaskViewController, :completed
    get "/trash", CommandController, :trash
    get "/organizations", CommandController, :organizations
    get "/mutations/:mutation_id", CommandController, :mutation
    get "/tasks/:task_id/activity", ActivityController, :index
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api, :authenticated, :mutation]

    post "/commands/capture-task", CommandController, :capture_task
    post "/commands/edit-task", CommandController, :edit_task
    post "/commands/clarify-task", CommandController, :clarify_task
    post "/commands/return-to-inbox", CommandController, :return_to_inbox
    post "/commands/complete-task", CommandController, :complete_task
    post "/commands/reopen-task", CommandController, :reopen_task
    post "/commands/trash-task", CommandController, :trash_task
    post "/commands/restore-task", CommandController, :restore_task
    post "/commands/resolve-task-conflict", CommandController, :resolve_task_conflict
    post "/commands/edit-task-dates", CommandController, :edit_task_dates
    post "/commands/plan-for-today", CommandController, :plan_for_today
    post "/commands/unplan-task", CommandController, :unplan_task
    post "/commands/move-today-task", TaskViewController, :move_today
    post "/commands/create-organization", CommandController, :create_organization
    post "/commands/rename-organization", CommandController, :rename_organization
    post "/commands/archive-organization", CommandController, :archive_organization
    post "/commands/unarchive-organization", CommandController, :unarchive_organization

    post "/commands/assign-task-organizations",
         CommandController,
         :assign_task_organizations

    post "/reauthenticate", AuthController, :reauthenticate
    post "/logout", AuthController, :logout
    patch "/sessions/:id", AuthController, :update_session
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api, :authenticated, :mutation, :recent_auth]

    delete "/sessions/:id", AuthController, :revoke_session
  end
end
