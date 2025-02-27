defmodule Dantex.Eval do
  require Logger

  @doc """
  Runs the evaluation process using the provided options.

  """

  alias Dantex.Agent
  alias Dantex.Eval.{TestCase, Metric}
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
      {:ok, {response, _all_messages, _updated_agent}, usage} ->
        # Get the actual output and update the test case
        updated_test_case = %{test_case | actual_output: response.content}

        # Calculate the score using the metric
        score = metric.score(metric, updated_test_case)

        # Determine pass/fail status
        pass = metric.score(score)

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
end
