defmodule Mix.Tasks.Keepling.Timezone do
  use Mix.Task

  @shortdoc "Changes the sole Keepling account's canonical IANA timezone"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    timezone =
      case args do
        [timezone] -> timezone
        _ -> Mix.raise("usage: mix keepling.timezone IANA_TIMEZONE")
      end

    case Keepling.Accounts.change_timezone(timezone) do
      {:ok, _result} ->
        Mix.shell().info("Account timezone updated. Affected views will refresh.")

      {:error, :invalid_timezone} ->
        Mix.raise("timezone must be a valid IANA name")

      {:error, :account_unavailable} ->
        Mix.raise("account timezone could not be changed")

      {:error, :infrastructure_failure} ->
        Mix.raise("account timezone could not be changed")
    end
  end
end
