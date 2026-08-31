defmodule Mix.Tasks.Keepling.SetupToken do
  use Mix.Task

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

    if positional != [] or invalid != [] or not valid_base_url?(base_url) or
         ttl_seconds < 60 or ttl_seconds > 3_600 do
      Mix.raise(
        "usage: mix keepling.setup_token --base-url https://keepling.example [--ttl-seconds 900]"
      )
    end

    case Keepling.Accounts.issue_setup_token(ttl_seconds: ttl_seconds) do
      {:ok, issued} ->
        token = URI.encode_www_form(issued.token)
        url = "#{String.trim_trailing(base_url, "/")}/setup?token=#{token}"

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

  defp valid_base_url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        true

      %URI{scheme: "http", host: host}
      when is_binary(host) and host in ["localhost", "127.0.0.1"] ->
        true

      _ ->
        false
    end
  end

  defp valid_base_url?(_value), do: false
end
