defmodule Mix.Tasks.Keepling.Recover do
  @shortdoc "Issues a one-use browser recovery link"

  use Mix.Task

  alias Keepling.Accounts

  @default_ttl_seconds 900

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {options, positional, invalid} =
      OptionParser.parse(args,
        strict: [base_url: :string, ttl_seconds: :integer],
        aliases: [u: :base_url, t: :ttl_seconds]
      )

    if positional != [] or invalid != [] do
      Mix.raise("usage: mix keepling.recover --base-url URL [--ttl-seconds SECONDS]")
    end

    base_url = Keyword.get(options, :base_url, "http://localhost:4000")
    ttl_seconds = Keyword.get(options, :ttl_seconds, @default_ttl_seconds)

    with {:ok, base_uri} <- validate_base_url(base_url),
         {:ok, issued} <- Accounts.issue_recovery_token(ttl_seconds: ttl_seconds) do
      query = URI.encode_query(%{"token" => issued.token})
      link = %{base_uri | path: "/recover", query: query, fragment: nil} |> URI.to_string()

      Mix.shell().info("Recovery link (shown once):")
      Mix.shell().info(link)
      Mix.shell().info("This link expires at #{DateTime.to_iso8601(issued.expires_at)}.")
    else
      {:error, :invalid_base_url} -> Mix.raise("base URL must be an absolute HTTP(S) URL")
      {:error, :invalid_ttl} -> Mix.raise("recovery lifetime must be between 60 and 3600 seconds")
      {:error, :account_unavailable} -> Mix.raise("recovery is unavailable")
      {:error, :infrastructure_failure} -> Mix.raise("recovery is temporarily unavailable")
    end
  end

  defp validate_base_url(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, %{uri | query: nil, fragment: nil}}

      _ ->
        {:error, :invalid_base_url}
    end
  end
end
