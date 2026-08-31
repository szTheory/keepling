defmodule KeeplingWeb.Router do
  use KeeplingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", KeeplingWeb do
    pipe_through :api
  end
end
