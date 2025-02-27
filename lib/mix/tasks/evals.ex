defmodule Mix.Tasks.Evals do
  @moduledoc """
  Runs LLM evaluations using Dantex.Eval.

  ## Usage

      $ mix evals --model MODEL_PATH --messages MESSAGES_PATH --results RESULTS_PATH

  ## Examples

      $ mix evals --model eval/initial_eval/model.yml --messages eval/initial_eval/messages.yml --results eval/initial_eval/results.yml
  """
  use Mix.Task

  alias Dantex.{Agent, Message}

  @shortdoc "Runs LLM evaluations"

  @impl Mix.Task
  def run(args) do
    # Start the applications needed for the evaluation
    # This is required because mix tasks don't start the application by default
    Application.ensure_all_started(:httpoison)
    Application.ensure_all_started(:goth)
    Application.ensure_all_started(:jason)

    # Manually start Goth if needed
    start_goth_authentication()

    IO.puts("Starting Dantex Evaluation")

    # Parse the command line arguments
    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [
          model: :string,
          messages: :string,
          results: :string
        ]
      )

    # Check if all required parameters are provided
    missing_params = Enum.filter(required_params, fn param -> is_nil(parsed[param]) end)

    if Enum.empty?(missing_params) do
    else
      # Display usage message if parameters are missing
      missing_list = Enum.map_join(missing_params, ", ", fn param -> "--#{param}" end)
      IO.puts("ERROR: Missing required parameters: #{missing_list}")

      IO.puts("""

      Usage: mix evals --model MODEL_PATH --messages MESSAGES_PATH --results RESULTS_PATH

      Example:
        mix evals --model eval/initial_eval/model.yml --messages eval/initial_eval/messages.yml --results eval/initial_eval/results.yml
      """)

      System.halt(1)
    end
  end

  # Helper function to format Elixir data structures as YAML
  defp format_yaml_data(data, indent_level) when is_map(data) do
    indent = String.duplicate("  ", indent_level)

    Enum.map_join(data, "\n", fn {key, value} ->
      "#{indent}#{key}: #{format_yaml_value(value, indent_level + 1)}"
    end)
  end

  defp format_yaml_value(value, indent_level) when is_binary(value) do
    # Check if the string needs to be quoted (contains special characters)
    if String.contains?(value, [
         ":",
         "{",
         "}",
         "[",
         "]",
         ",",
         "&",
         "*",
         "#",
         "?",
         "|",
         "-",
         "<",
         ">",
         "=",
         "!",
         "%",
         "@",
         "\\"
       ]) or
         String.match?(value, ~r/\n/) do
      # For multiline strings, use the literal block scalar (|)
      if String.match?(value, ~r/\n/) do
        indent_str = String.duplicate("  ", indent_level)

        indented_lines =
          String.split(value, "\n")
          |> Enum.map_join("\n", fn line -> String.duplicate("  ", indent_level + 1) <> line end)

        "\n" <> indent_str <> "|\n" <> indented_lines
      else
        # Quote the string if it contains special characters
        "\"#{String.replace(value, "\"", "\\\"")}\""
      end
    else
      value
    end
  end

  defp format_yaml_value(nil, _indent_level) do
    "null"
  end

  defp format_yaml_value(value, _indent_level)
       when is_number(value) or is_boolean(value) do
    "#{value}"
  end

  defp format_yaml_value(value, indent_level) when is_list(value) do
    if Enum.empty?(value) do
      "[]"
    else
      "\n" <>
        Enum.map_join(value, "\n", fn item ->
          indent = String.duplicate("  ", indent_level)
          "#{indent}- #{format_yaml_value(item, indent_level + 1)}"
        end)
    end
  end

  defp format_yaml_value(value, _indent_level) do
    "#{inspect(value)}"
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
