defmodule Dantex.Eval do
  @moduledoc """
  Runs the evaluation process and print the results to an HTML file
  """

  alias Dantex.Agent
  alias Dantex.Eval.{TestCase, Metric, RegexMatchMetric}
  require Logger

  @doc """
  Runs an evaluation for a single test case using the provided metric.

  The function:
  1. Takes a metric and a TestCase
  2. Runs the test case through the model
  3. Updates the test case with the actual output
  4. Scores the output using the provided metric
  5. Returns a map with the evaluation results

  ## Parameters
    * `metric` - Metric module to use for scoring
    * `test_case` - TestCase struct containing input and expected output
    * `model` - Model to run the evaluation against

  ## Returns
    A map containing:
    * `input` - The input from the test case
    * `expected_output` - The expected output from the test case
    * `actual_output` - The actual output from the LLM
    * `tokens_used` - Number of tokens used by the LLM
    * `pass` - Boolean indicating pass/fail status
    * `score` - Score from the metric (0-1)

  ## Examples

      iex> metric = Dantex.Eval.RegexMatchMetric
      iex> test_case = Dantex.Eval.TestCase.new([Dantex.Message.user("What is 2+2?")], "4")
      iex> agent = Dantex.Agent.new(:openai, "gpt-4")
      iex> {:ok, result} = Dantex.Eval.run(agent, test_case, metric)
      iex> result.pass
      true
  """
  @spec run(Agent.t(), TestCase.t(), Metric.t()) ::
          {:ok, TestCase.t()} | {:error, term()}
  def run(%Agent{} = agent, %TestCase{} = test_case, metric) do
    last_message = List.last(test_case.input)
    updated_agent = %{agent | messages: Enum.drop(test_case.input, -1)}

    case Agent.run(updated_agent, last_message) do
      {:ok, {response, _all_messages, _updated_agent, _formatted_results}, usage} ->
        # Get the actual output and update the test case
        updated_test_case = %{test_case | actual_output: response.content}

        # TODO we need to make this more flexible for differen metric types
        # Calculate the score using the metric
        score = RegexMatchMetric.score(metric, updated_test_case)

        # Determine pass/fail status
        pass = RegexMatchMetric.pass(score)

        # Get tokens used - this would need to be extended when actual token
        # information is available from Model.chat_completion
        tokens_used = Map.get(usage, :total_tokens, 0)

        {:ok,
         TestCase.set_result(test_case, %{
           actual_output: response.content,
           score: score,
           pass: pass,
           tokens: tokens_used
         })}

      {:error, error} ->
        {:error, "Evaluation failed: #{inspect(error)}"}
    end
  end

  @doc """
  Runs evaluations for multiple test cases using the provided agent and metric.

  The function:
  1. Takes an agent, an array of test cases, and a metric
  2. Runs each test case through the model
  3. Collects the results
  4. Optionally prints the results to an HTML file
  5. Returns a list of the evaluation results

  ## Parameters
    * `agent` - Agent struct containing the model to use
    * `test_cases` - List of TestCase structs
    * `metric` - Metric module to use for scoring
    * `opts` - Options map with the following keys:
      * `:results_path` - (Required) Path to save the HTML results

  ## Returns
    A tuple containing:
    * `:ok` - Indicating success
    * List of tuples, each containing either:
      * `{:ok, test_case}` - The updated test case with results
      * `{:error, reason}` - The error that occurred

  ## Examples

      iex> metric = Dantex.Eval.RegexMatchMetric
      iex> test_cases = [
      ...>   Dantex.Eval.TestCase.new([Dantex.Message.user("What is 2+2?")], "4"),
      ...>   Dantex.Eval.TestCase.new([Dantex.Message.user("What is 3+3?")], "6")
      ...> ]
      iex> agent = Dantex.Agent.new(:openai, "gpt-4")
      iex> {:ok, results} = Dantex.Eval.run_all(results_path, agent, test_cases, metric)
  """
  @spec run_all(String.t(), Agent.t(), Metric.t(), [TestCase.t()]) ::
          {:ok, [TestCase.t()]} | {:error, term()}
  def run_all(results_path, %Agent{} = agent, metric, test_cases) when is_list(test_cases) do

    # Run each test case and collect results
    test_case_results =
      Enum.map(test_cases, fn test_case ->
        case run(agent, test_case, metric) do
          {:ok, result} -> {:ok, result}
          {:error, error} ->
            Logger.error("Test case failed: #{inspect(error)}")
            {:error, error}
        end
      end)

    error_index = Enum.find_index(test_case_results, fn result ->
      match?({:error, _}, result)
    end)

    case error_index do
      nil ->
        # Strip the ok/error atoms and ensure only TestCase.t() elements
        test_cases =
          Enum.map(test_case_results, fn
            {:ok, result} -> result
            _ -> nil # Skip errors or unexpected cases
          end)
          |> Enum.filter(&(&1 != nil))

        # Print summary to console
        print_console_summary(test_cases)
        print_html_results(results_path, agent, metric, test_cases)
        {:ok, test_case_results}

      _ ->
        {:error, "Evaluation failed for one or more test cases"}
    end
  end

  # Helper function to print a summary to the console
  @spec print_console_summary([TestCase.t()]) :: nil
  defp print_console_summary(test_cases) do
    total_tests = length(test_cases)
    passed_tests = Enum.count(test_cases, fn
      %Dantex.Eval.TestCase{pass: pass} -> pass
      _ -> false
    end)
    overall_score = if total_tests > 0, do: passed_tests / total_tests * 100, else: 0.0

    total_tokens =
      Enum.reduce(test_cases, 0, fn
        %Dantex.Eval.TestCase{tokens: tokens}, acc -> (tokens || 0) + acc
        _ , acc -> acc
      end)

    IO.puts("\n=== Evaluation Summary ===")
    IO.puts(
      "Tests: #{total_tests} | Passed: #{passed_tests} | Failed: #{total_tests - passed_tests}"
    )
    # Ensure we're passing floats to Float.round
    formatted_score = if is_integer(overall_score), do: overall_score * 1.0, else: overall_score
    estimated_cost = total_tokens / 1000 * 0.01
    IO.puts("Overall Score: #{Float.round(formatted_score, 2)}%")
    IO.puts("Total Tokens: #{total_tokens}")
    IO.puts("Estimated Cost: $#{Float.round(estimated_cost, 4)} USD")
    IO.puts("========================\n")
    nil
  end

  @spec print_html_results(String.t(), Agent.t(), Metric.t(), [TestCase.t()]) ::
          {:ok} | {:error, term()}
  def print_html_results(path, %Agent{model: model }, _metric, test_cases) do
    try do
      # Calculate overall statistics
      total_tests = length(test_cases)
      passed_tests = Enum.count(test_cases, & &1.pass)
      overall_score = if total_tests > 0, do: passed_tests / total_tests, else: 0.0

      total_tokens =
        Enum.reduce(test_cases, 0, fn test_case, acc -> (test_case.tokens || 0) + acc end)

      # Estimate cost (assuming OpenAI GPT-4 pricing of $0.01 per 1K tokens)
      estimated_cost = total_tokens / 1000 * 0.01

      # Generate timestamp and filename
      # Format timestamp as YYYY-MM-DD_HH-MM for shorter filenames
      timestamp = DateTime.utc_now()
                  |> Calendar.strftime("%Y-%m-%d_%H-%M")

      # Extract just the provider name without the Elixir.Dantex.Providers prefix
      provider_full = model.provider |> to_string()
      provider = provider_full
                 |> String.split(".")
                 |> List.last()

      model_name = model.model
      filename = "#{timestamp}_#{provider}-#{model_name}.html"
      full_path = Path.join(path, filename)

      # Create HTML content
      html_content = """
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Evaluation Results</title>
        <link rel="stylesheet" href="//cdn.datatables.net/2.2.2/css/dataTables.dataTables.min.css">
        <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
        <script src="//cdn.datatables.net/2.2.2/js/dataTables.min.js"></script>
        <style>
          body { font-family: Arial, sans-serif; margin: 20px; }
          .summary { margin-bottom: 20px; padding: 15px; background-color: #f8f9fa; border-radius: 5px; }
          .summary h2 { margin-top: 0; }
          .summary-item { margin-bottom: 10px; }
          .pass { color: green; }
          .fail { color: red; }
          table { width: 100%; border-collapse: collapse; }
          th, td { padding: 8px; text-align: left; }
          pre { white-space: pre-wrap; max-height: 200px; overflow-y: auto; }
        </style>
      </head>
      <body>
        <div class="summary">
          <h2>Evaluation Summary</h2>
          <div class="summary-item"><strong>Provider/Model:</strong> #{provider}/#{model_name}</div>
          <div class="summary-item"><strong>Metric:</strong> #{"RegexMatch" |> to_string() |> String.split(".") |> List.last()}</div>
          <div class="summary-item"><strong>Overall Score:</strong> #{Float.round(overall_score * 100, 2)}% (#{passed_tests}/#{total_tests} tests passed)</div>
          <div class="summary-item"><strong>Total Tokens Used:</strong> #{total_tokens}</div>
          <div class="summary-item"><strong>Estimated Cost:</strong> $#{Float.round(estimated_cost, 4)} USD</div>
        </div>

        <h2>Test Results</h2>
        <table id="results-table" class="display">
          <thead>
            <tr>
              <th>Test #</th>
              <th>Input</th>
              <th>Expected Output</th>
              <th>Actual Output</th>
              <th>Score</th>
              <th>Pass/Fail</th>
              <th>Tokens</th>
            </tr>
          </thead>
          <tbody>
            #{generate_table_rows(test_cases)}
          </tbody>
        </table>

        <script>
          $(document).ready(function() {
            $('#results-table').DataTable({
              paging: true,
              searching: true,
              ordering: true
            });
          });
        </script>
      </body>
      </html>
      """

      # Ensure directory exists
      File.mkdir_p!(Path.dirname(full_path))

      # Write the file
      case File.write(full_path, html_content) do
        :ok ->
          {:ok}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Failed to generate results #{inspect(e)}")
        {:error, e}
    end
  end

  # Helper function to generate table rows for each test case
  # @doc false - Exposed for testing
  def generate_table_rows(test_cases) do
    test_cases
    |> Enum.with_index(1)
    |> Enum.map(fn {test_case, index} ->
      input_text = format_messages(test_case.input)
      expected = test_case.expected_output || "N/A"
      actual = test_case.actual_output || "N/A"
      score = test_case.score || 0.0
      pass_class = if test_case.pass, do: "pass", else: "fail"
      pass_text = if test_case.pass, do: "PASS", else: "FAIL"
      tokens = test_case.tokens || 0

      # Format score - handle both integers and floats
      formatted_score = if is_integer(score), do: score * 1.0, else: Float.round(score, 2)

      """
      <tr>
        <td>#{index}</td>
        <td><pre>#{html_escape(input_text)}</pre></td>
        <td><pre>#{html_escape(expected)}</pre></td>
        <td><pre>#{html_escape(actual)}</pre></td>
        <td>#{formatted_score}</td>
        <td class="#{pass_class}">#{pass_text}</td>
        <td>#{tokens}</td>
      </tr>
      """
    end)
    |> Enum.join("\n")
  end

  # Helper function to format messages for display
  # @doc false - Exposed for testing
  def format_messages(messages) do
    messages
    |> Enum.map(fn msg ->
      role = Map.get(msg, :role, "unknown")
      content = Map.get(msg, :content, "")
      "#{role}: #{content}"
    end)
    |> Enum.join("\n\n")
  end

  # Helper function to escape HTML special characters
  # @doc false - Exposed for testing
  def html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  def html_escape(nil), do: ""
  def html_escape(other), do: html_escape(to_string(other))
end
