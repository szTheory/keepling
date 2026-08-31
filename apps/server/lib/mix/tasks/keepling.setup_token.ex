defmodule Mix.Tasks.Keepling.SetupToken do
  use Mix.Task

  alias Keepling.OperatorBaseURL

  @shortdoc "Issues Keepling's one-time first-account setup link"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [base_url: :string, ttl_seconds: :integer]
      )

    base_url = opts[:base_url]
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 900)

    if positional != [] or invalid != [] or ttl_seconds < 60 or ttl_seconds > 3_600 do
      Mix.raise(
        "usage: mix keepling.setup_token --base-url HTTPS_URL [--ttl-seconds 900]; HTTP is allowed only for loopback addresses and userinfo is forbidden"
      )
    end

    base_uri =
      case OperatorBaseURL.validate(base_url) do
        {:ok, uri} ->
          uri

        {:error, :invalid_base_url} ->
          Mix.raise(
            "base URL must use HTTPS, or HTTP only for a loopback address, and must not include userinfo"
          )
      end

    case Keepling.Accounts.issue_setup_token(ttl_seconds: ttl_seconds) do
      {:ok, issued} ->
        url = OperatorBaseURL.capability_link(base_uri, "/setup", issued.token)

        Mix.shell().info("Setup link (shown once): #{url}")
        Mix.shell().info("This link expires at #{DateTime.to_iso8601(issued.expires_at)}.")

      {:error, :setup_token_active} ->
        Mix.raise("a setup link is already active")

      {:error, :setup_disabled} ->
        Mix.raise("setup is permanently disabled")

      {:error, :invalid_ttl} ->
        Mix.raise("setup link lifetime must be between 60 and 3600 seconds")

      {:error, :infrastructure_failure} ->
        Mix.raise("setup link could not be issued")
    end
  end
end
