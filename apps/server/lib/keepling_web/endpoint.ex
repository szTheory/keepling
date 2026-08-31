defmodule KeeplingWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :keepling

  @session_options [
    store: :cookie,
    key: "_keepling_key",
    signing_salt: "ME4c4Ieh",
    http_only: true,
    same_site: "Lax",
    secure: Mix.env() == :prod
  ]

  plug Plug.Static,
    at: "/",
    from: :keepling,
    gzip: not code_reloading?,
    only: KeeplingWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :keepling
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug KeeplingWeb.Router
end
