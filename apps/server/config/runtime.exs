import Config

environment = config_env()

fetch_required! = fn key ->
  case System.fetch_env(key) do
    {:ok, value} when value != "" ->
      value

    _ ->
      raise "configuration error in #{environment}: #{key} is required"
  end
end

positive_integer! = fn key, default ->
  value = System.get_env(key, default)

  case Integer.parse(value) do
    {integer, ""} when integer > 0 ->
      integer

    _ ->
      raise "configuration error in #{environment}: #{key} must be a positive integer"
  end
end

enabled? = fn key ->
  case System.get_env(key) do
    nil -> false
    value when value in ["false", "0"] -> false
    value when value in ["true", "1"] -> true
    _ -> raise "configuration error in #{environment}: #{key} must be true, false, 1, or 0"
  end
end

{database_url_key, secret_key_base_key} =
  case environment do
    :dev -> {"KEEPLING_DEV_DATABASE_URL", "KEEPLING_DEV_SECRET_KEY_BASE"}
    :test -> {"KEEPLING_TEST_DATABASE_URL", "KEEPLING_TEST_SECRET_KEY_BASE"}
    :prod -> {"DATABASE_URL", "SECRET_KEY_BASE"}
  end

database_url = fetch_required!.(database_url_key)
secret_key_base = fetch_required!.(secret_key_base_key)

if byte_size(secret_key_base) < 64 do
  raise "configuration error in #{environment}: #{secret_key_base_key} must be at least 64 bytes"
end

database_socket_options = if enabled?.("ECTO_IPV6"), do: [:inet6], else: []

config :keepling, Keepling.Repo,
  url: database_url,
  pool_size: positive_integer!.("POOL_SIZE", "10"),
  socket_options: database_socket_options

endpoint_ipv6? = enabled?.("PHX_IPV6")

endpoint_ip =
  case {environment, endpoint_ipv6?} do
    {:prod, false} -> {0, 0, 0, 0}
    {:prod, true} -> {0, 0, 0, 0, 0, 0, 0, 0}
    {_, false} -> {127, 0, 0, 1}
    {_, true} -> {0, 0, 0, 0, 0, 0, 0, 1}
  end

default_http_port = if environment == :test, do: "4002", else: "4000"

endpoint_url =
  if environment == :prod do
    [
      host: fetch_required!.("PHX_HOST"),
      port: positive_integer!.("PHX_URL_PORT", "443"),
      scheme: "https"
    ]
  else
    [
      host: "localhost",
      port: positive_integer!.("PHX_URL_PORT", default_http_port),
      scheme: "http"
    ]
  end

config :keepling, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

compatibility = Application.fetch_env!(:keepling, :compatibility)

compatibility =
  if environment == :prod do
    compatibility
    |> Map.put("server_release", System.get_env("KEEPLING_SERVER_RELEASE"))
    |> Map.put("tested_oci_digest", System.get_env("KEEPLING_TESTED_OCI_DIGEST"))
    |> Map.put("update_location", System.get_env("KEEPLING_UPDATE_LOCATION"))
  else
    compatibility
  end

config :keepling, :compatibility, compatibility

operator_status_token =
  case {environment, System.get_env("KEEPLING_OPERATOR_TOKEN")} do
    {:prod, nil} -> fetch_required!.("KEEPLING_OPERATOR_TOKEN")
    {:prod, ""} -> fetch_required!.("KEEPLING_OPERATOR_TOKEN")
    {_environment, value} -> value
  end

operator_status_token_hash =
  case operator_status_token do
    nil ->
      nil

    token when byte_size(token) >= 32 ->
      :crypto.hash(:sha256, token)

    _ ->
      raise "configuration error in #{environment}: KEEPLING_OPERATOR_TOKEN must be at least 32 bytes"
  end

config :keepling, :operator_status_token_hash, operator_status_token_hash

# O-18: the device-grant namespace and redirect allowlist a REAL server
# boots with. Previously these existed only inside test setup, which made
# `/oauth/authorize` answer 400 for every request on a running server and
# `namespace_config/0` return `:device_grant_configuration_missing`.
#
# `issuer`, `origin`, and `server_instance` are three of the five locked
# namespace-tuple fields and are SERVER-DERIVED ONLY -- they come from
# deployment configuration here and can never be influenced by request
# input. `server_instance` must be stable for the life of a server's data:
# changing it opens a new synchronization namespace, which is exactly the
# fence a restore-onto-different-server needs.
#
# The redirect allowlist is an exact-match private-use-scheme allowlist
# (RFC 8252): the desktop app registers `keepling://` and the server accepts
# only the precise callback URI, never a prefix or a wildcard.
device_grant_origin =
  case environment do
    :prod -> System.get_env("KEEPLING_DEVICE_GRANT_ORIGIN") || "https://#{endpoint_url[:host]}"
    _ -> System.get_env("KEEPLING_DEVICE_GRANT_ORIGIN") || "http://localhost:#{endpoint_url[:port]}"
  end

device_grant_issuer = System.get_env("KEEPLING_DEVICE_GRANT_ISSUER") || device_grant_origin

device_grant_server_instance =
  case {environment, System.get_env("KEEPLING_DEVICE_GRANT_SERVER_INSTANCE")} do
    {:prod, nil} -> fetch_required!.("KEEPLING_DEVICE_GRANT_SERVER_INSTANCE")
    {:prod, ""} -> fetch_required!.("KEEPLING_DEVICE_GRANT_SERVER_INSTANCE")
    {_environment, nil} -> "local-#{environment}"
    {_environment, value} -> value
  end

config :keepling, :device_grants,
  issuer: device_grant_issuer,
  origin: device_grant_origin,
  server_instance: device_grant_server_instance,
  redirect_uris: %{
    "electron" => ["keepling://auth/callback"],
    # 04-07-PLAN.md Task 1: the iPhone app's ASWebAuthenticationSession
    # callback is distinct from the desktop's `keepling://auth/callback`,
    # but distinguishes itself by HOST (`ios`) rather than by scheme.
    # redirect_uris!/1 in application.ex requires every allowlist entry to
    # be an exact private-use `keepling://host/path` URI; a separate
    # `keeplingios` scheme violates that invariant, and widening the
    # validator to accept arbitrary schemes would weaken the allowlist for
    # every client. A private-use scheme is first-come per-OS, so desktop
    # and iPhone sharing `keepling` cannot collide -- they never register
    # on the same OS.
    "iphone" => ["keepling://ios/auth/callback"]
  }

config :keepling, KeeplingWeb.Endpoint,
  server: enabled?.("PHX_SERVER"),
  url: endpoint_url,
  http: [ip: endpoint_ip, port: positive_integer!.("PORT", default_http_port)],
  secret_key_base: secret_key_base
