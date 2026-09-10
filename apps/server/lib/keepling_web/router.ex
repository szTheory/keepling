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

  pipeline :device_grant_authenticated do
    plug KeeplingWeb.Auth, :authenticate_device_grant
  end

  # D-03: agent traffic mounts through its own pipeline on the existing
  # Phoenix router rather than a sidecar, so it is subject to the same
  # request-level posture (JSON body parsing, session-free bearer auth) as
  # every other native-client pipeline. `KeeplingWeb.MCP.Pipeline` performs
  # the device-grant authentication and the `client_kind == "mcp"` refusal.
  pipeline :mcp do
    plug KeeplingWeb.MCP.Pipeline
  end

  # D-49. Either credential class, each judged by its own rules.
  pipeline :client_authenticated do
    plug KeeplingWeb.Auth, :authenticate_client
  end

  pipeline :client_mutation do
    plug KeeplingWeb.Auth, :authenticate_client_mutation
    plug KeeplingWeb.CommandDiscriminator
  end

  pipeline :test_fixture do
    plug KeeplingWeb.Auth, :require_test_fixture
    plug :protect_from_forgery
  end

  if Mix.env() == :test do
    pipeline :test_fault do
      plug KeeplingWeb.TestFaultController
    end

    scope "/api/v1/test", KeeplingWeb do
      pipe_through [:api, :test_fixture]

      post "/session", CommandController, :test_session
    end
  end

  mutation_pipelines =
    if Mix.env() == :test,
      do: [:api, :authenticated, :mutation, :test_fault],
      else: [:api, :authenticated, :mutation]

  # D-49: the SHARED command surface -- the one place a mutation is accepted
  # from any adapter. `:client_mutation` admits either credential class and
  # applies each one's own guards (see KeeplingWeb.Auth#authenticate_client);
  # it does NOT relax anything for the browser. Session-management routes are
  # deliberately NOT here: they stay browser-only below.
  command_pipelines =
    if Mix.env() == :test,
      do: [:api, :client_mutation, :test_fault],
      else: [:api, :client_mutation]

  recent_auth_mutation_pipelines =
    if Mix.env() == :test,
      do: [:api, :authenticated, :mutation, :recent_auth, :test_fault],
      else: [:api, :authenticated, :mutation, :recent_auth]

  scope "/", KeeplingWeb do
    pipe_through [:api]

    get "/compatibility", CompatibilityController, :show
    get "/health/live", HealthController, :live
    get "/health/ready", HealthController, :ready
    get "/ops/status", HealthController, :status
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api]

    post "/setup", AuthController, :setup
  end

  scope "/oauth", KeeplingWeb do
    pipe_through [:api]

    post "/token", DeviceGrantController, :token
    post "/token/refresh", DeviceGrantController, :token
  end

  scope "/oauth", KeeplingWeb do
    pipe_through [:api, :authenticated]

    get "/authorize", DeviceGrantController, :authorize
  end

  # D-29: RFC 7591 Dynamic Client Registration, scoped behind the owner's
  # authenticated browser session -- never reachable by an unauthenticated
  # caller (T-05-08/T-05-09).
  scope "/oauth", KeeplingWeb.MCP do
    pipe_through [:api, :authenticated, :mutation]

    post "/register", Registration, :create
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through [:api, :device_grant_authenticated]

    get "/device-grants", DeviceGrantController, :list
    delete "/device-grants/:installation_id", DeviceGrantController, :revoke
    get "/sync", SyncController, :pull
    get "/sync/bootstrap", SyncController, :bootstrap
  end

  scope "/mcp", KeeplingWeb.MCP do
    pipe_through [:api, :mcp]

    post "/v1", Dispatch, :handle
  end

  # RFC 9728 / RFC 8414 discovery -- unauthenticated by specification (T-05-12).
  scope "/.well-known", KeeplingWeb.MCP do
    pipe_through [:api]

    get "/oauth-protected-resource", Metadata, :protected_resource
    get "/oauth-authorization-server", Metadata, :authorization_server
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
    get "/today/mutations/:mutation_id", TaskViewController, :mutation
    get "/tasks/:task_id", CommandController, :task
    get "/tasks/:task_id/activity", ActivityController, :index
  end

  # D-49. A client that may ISSUE a mutation must be able to read that
  # mutation's exact stored receipt -- reconciliation after a dropped
  # connection is the whole reason an offline client keeps a mutation
  # identity. Read and write move together, or the write is unsettleable.
  scope "/api/v1", KeeplingWeb do
    pipe_through [:api, :client_authenticated]

    get "/mutations/:mutation_id", CommandController, :mutation
    get "/projects", ProjectController, :index
    get "/projects/:organization_id/tasks", ProjectController, :tasks
  end

  # D-09: the one genuinely missing read capability, shared by every
  # `:client_authenticated` credential class (browser session, Electron,
  # iPhone, and `mcp` device grants alike) -- not an MCP-only code path.
  scope "/", KeeplingWeb do
    pipe_through [:api, :client_authenticated]

    get "/api/v1/search", SearchController, :index
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through command_pipelines

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
    post "/commands/undo-task", CommandController, :undo_task
    post "/commands/move-today-task", TaskViewController, :move_today
    post "/commands/create-organization", CommandController, :create_organization
    post "/commands/rename-organization", CommandController, :rename_organization
    post "/commands/archive-organization", CommandController, :archive_organization
    post "/commands/unarchive-organization", CommandController, :unarchive_organization

    post "/commands/assign-task-organizations",
         CommandController,
         :assign_task_organizations
  end

  # Session management is NOT part of the shared command surface. A device
  # grant must never be able to mint, rename, or end a BROWSER session, so
  # these keep the browser-only pipeline they have always had.
  scope "/api/v1", KeeplingWeb do
    pipe_through mutation_pipelines

    post "/reauthenticate", AuthController, :reauthenticate
    post "/logout", AuthController, :logout
    patch "/sessions/:id", AuthController, :update_session
  end

  scope "/api/v1", KeeplingWeb do
    pipe_through recent_auth_mutation_pipelines

    delete "/sessions/:id", AuthController, :revoke_session
  end
end
