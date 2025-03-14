defmodule Mix.Tasks.Evals.Run do
  @moduledoc """
  Runs a specific evaluation if it's not already in the cache.

  ## Usage

      $ mix evals.run eval_name [--provider PROVIDER] [--model MODEL]

  Options:
    * `--provider` - The provider to use (e.g., openai, ollama, gemini)
    * `--model` - The model to use (e.g., gpt-4, llama2, gemini-pro)

  This task checks if the specified evaluation has already been run (by checking the .dantex-cache file).
  If not, it runs the evaluation and adds it to the cache.
  """
  use Mix.Task
  alias Dantex.Eval

  @shortdoc "Runs a specific evaluation"

  @impl Mix.Task
  def run(args) do
    # Load runtime configuration
    Mix.Task.run("app.config")

    # Start the applications needed for the evaluation
    Application.ensure_all_started(:dantex)
    Application.ensure_all_started(:httpoison)
    Application.ensure_all_started(:goth)
    Application.ensure_all_started(:jason)
    Application.ensure_all_started(:finch)
    Application.ensure_all_started(:openai_ex)

    # Manually start Goth if needed
    start_goth_authentication()

    # Parse options
    {opts, remaining_args, _} = OptionParser.parse(args,
      strict: [
        provider: :string,
        model: :string
      ]
    )

    provider = Keyword.get(opts, :provider)
    model = Keyword.get(opts, :model)

    case remaining_args do
      [eval_name] ->
        run_evaluation(eval_name, provider, model)

      _ ->
        IO.puts("""
        ERROR: Missing evaluation name

        Usage: mix evals.run EVAL_NAME [--provider PROVIDER] [--model MODEL]

        Example:
          mix evals.run my_evaluation
          mix evals.run my_evaluation --provider openai --model gpt-4
        """)

        System.halt(1)
    end
  end

  @doc """
  Coordinates the evaluation process by calling specialized functions in sequence.
  """
  @spec run_evaluation(String.t(), String.t() | nil, String.t() | nil) :: no_return()
  defp run_evaluation(eval_name, provider, model) do
    IO.puts("Running evaluation: #{eval_name}")

    if provider, do: IO.puts("Using provider: #{provider}")
    if model, do: IO.puts("Using model: #{model}")

    eval_file = verify_evaluation_exists(eval_name)
    cache_path = verify_cache_exists()
    cache_content = read_cache(cache_path)

    check_if_already_run(cache_content, eval_name)

    eval_module = load_evaluation_module(eval_file, eval_name)
    execute_evaluation(eval_module, eval_name, cache_content, cache_path, provider, model)
  end

  @doc """
  Verifies that the evaluation file exists and returns its path.
  Halts execution if the file doesn't exist.
  """
  @spec verify_evaluation_exists(String.t()) :: String.t()
  defp verify_evaluation_exists(eval_name) do
    eval_dir = Path.join("evals", eval_name)
    eval_file = Path.join(eval_dir, "eval.ex")

    unless File.exists?(eval_file) do
      IO.puts(
        "ERROR: Evaluation '#{eval_name}' not found. Make sure the directory evals/#{eval_name} exists with an eval.ex file."
      )

      System.halt(1)
    end

    eval_file
  end

  @doc """
  Verifies that the cache file exists and returns its path.
  Halts execution if the file doesn't exist.
  """
  @spec verify_cache_exists() :: String.t()
  defp verify_cache_exists do
    cache_path = Path.join("evals", ".dantex-cache")

    unless File.exists?(cache_path) do
      IO.puts("ERROR: .dantex-cache file not found. Run 'mix evals.setup' first.")
      System.halt(1)
    end

    cache_path
  end

  @doc """
  Reads and parses the cache file.
  """
  @spec read_cache(String.t()) :: map()
  defp read_cache(cache_path) do
    cache_path
    |> File.read!()
    |> Jason.decode!(keys: :atoms)
  end

  @doc """
  Checks if the evaluation has already been run.
  Halts execution if it has.
  """
  @spec check_if_already_run(map(), String.t()) :: :ok | no_return()
  defp check_if_already_run(cache_content, eval_name) do
    if Enum.any?(cache_content.evaluations, &(&1.name == eval_name)) do
      IO.puts("Evaluation '#{eval_name}' has already been run. Skipping.")
      System.halt(0)
    end

    :ok
  end

  @doc """
  Loads the evaluation module and returns its atom.
  """
  @spec load_evaluation_module(String.t(), String.t()) :: atom()
  defp load_evaluation_module(eval_file, eval_name) do
    # Load the evaluation module
    Code.require_file(eval_file)

    # Get the evaluation module name
    module_name = "Elixir.Dantex.Eval.#{Macro.camelize(eval_name)}"
    String.to_existing_atom(module_name)
  end

  @doc """
  Executes the evaluation and handles any errors.
  """
  @spec execute_evaluation(atom(), String.t(), map(), String.t(), String.t() | nil, String.t() | nil) :: no_return()
  defp execute_evaluation(eval_module, eval_name, cache_content, cache_path, provider, model) do
    IO.puts("Executing evaluation...")

    # Create a results directory if it doesn't exist
    results_dir = Path.join(["evals", eval_name, "results"])
    File.mkdir_p!(results_dir)

    # Create an agent if provider and model are specified
    agent = if provider && model do
      # Ensure the provider atom exists before using it
      provider_atom = String.to_atom(provider)
      Dantex.Agent.new(provider: provider_atom, model: model)
    else
      nil
    end

    # Pass the agent to the eval module's run function
    case apply(eval_module, :run, [agent]) do
      {:ok, agent, metric, test_cases} ->
        apply(Eval, :run_all, [results_dir, agent, metric, test_cases])

      {:error, error} ->
        IO.puts("ERROR: Evaluation failed: #{inspect(error)}")
        System.halt(1)
    end
  end

  @doc """
  Updates the cache with the evaluation results.
  """
  @spec update_cache(map(), String.t(), String.t(), any()) :: :ok
  defp update_cache(cache_content, cache_path, eval_name, result) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    updated_evaluations = [
      %{name: eval_name, timestamp: timestamp, result: result}
      | cache_content.evaluations
    ]

    updated_cache = %{cache_content | evaluations: updated_evaluations}

    # Write the updated cache back to the file
    updated_json = Jason.encode!(updated_cache, pretty: true)
    File.write!(cache_path, updated_json)

    :ok
  end

  # Initialize ETS tables and other required state for the task
  defp start_goth_authentication do
    # First, ensure ETS table exists for Goth
    try do
      :ets.new(:goth_tokens, [:set, :named_table, :public])
      IO.puts("Created goth_tokens ETS table")
    rescue
      # Table might already exist, which is fine
      ArgumentError -> IO.puts("ETS table :goth_tokens already exists")
    end

    # Create a dummy token for testing, in case authentication fails
    insert_dummy_token = fn ->
      :ets.insert(
        :goth_tokens,
        {"https://www.googleapis.com/auth/cloud-platform",
         %{
           token: "dummy_test_token",
           expires: :os.system_time(:seconds) + 3600
         }}
      )

      IO.puts("Inserted dummy token for testing purposes")
    end

    case System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON") do
      nil ->
        IO.puts("Warning: GOOGLE_APPLICATION_CREDENTIALS_JSON environment variable not set")
        insert_dummy_token.()
        :ok

      credentials_json ->
        try do
          credentials =
            credentials_json
            |> Jason.decode!()
            |> Map.update!("private_key", fn key ->
              key |> String.replace("\\n", "\n")
            end)

          source = {:service_account, credentials}

          case Goth.start_link(name: WebplayEx.Goth, source: source) do
            {:ok, _pid} ->
              IO.puts("Goth authentication started successfully")
              :ok

            {:error, {:already_started, _pid}} ->
              IO.puts("Goth authentication already started")
              :ok

            {:error, error} ->
              IO.puts("Failed to start Goth authentication: #{inspect(error)}")
              insert_dummy_token.()
              :ok
          end
        rescue
          e ->
            IO.puts("Error in Goth authentication: #{inspect(e)}")
            insert_dummy_token.()
            :ok
        end
    end
  end
end
