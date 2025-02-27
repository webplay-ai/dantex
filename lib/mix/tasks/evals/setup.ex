defmodule Mix.Tasks.Evals.Setup do
  @moduledoc """
  Sets up the evals directory structure and cache file.

  ## Usage

      $ mix evals.setup

  This task creates the evals directory structure and initializes the .dantex-cache file
  which tracks evaluations that have been run.
  """
  use Mix.Task

  @shortdoc "Sets up the evals directory structure"

  @impl Mix.Task
  def run(_args) do
    IO.puts("Setting up Dantex evaluations directory...")

    # Create the evals directory if it doesn't exist
    evals_dir = "evals"
    File.mkdir_p!(evals_dir)

    # Create the .dantex-cache file if it doesn't exist
    cache_path = Path.join(evals_dir, ".dantex-cache")

    unless File.exists?(cache_path) do
      # Initialize with an empty list of evaluations
      cache_content = %{
        evaluations: []
      }

      # Convert to JSON and write to file
      json = Jason.encode!(cache_content, pretty: true)
      File.write!(cache_path, json)

      IO.puts("Created #{cache_path} file")
    else
      IO.puts("#{cache_path} file already exists")
    end

    IO.puts("Dantex evaluations setup complete!")
  end
end
