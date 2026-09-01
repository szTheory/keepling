defmodule Mix.Tasks.Keepling.Ops do
  @shortdoc "Runs Keepling's stable operations vocabulary"
  @requirements ["app.config"]

  use Mix.Task

  @impl Mix.Task
  def run(args), do: Keepling.Release.ops(args)
end
