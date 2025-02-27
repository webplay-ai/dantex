defmodule Dantex.Eval.RegexMatchMetric do
  @moduledoc """
  A metric that evaluates LLM outputs based on regular expression matching.
  Returns a score of 1 if the output matches the provided regex pattern, 0 otherwise.
  """

  @behaviour Dantex.Eval.Metric
  alias Dantex.Eval.TestCase
  alias Dantex.Eval.Metric

  @doc """
  Scores an actual output against a regex pattern.
  Returns 1 if the output matches the pattern, 0 otherwise.

  ## Parameters
    * `regex` - String or Regex pattern to match against
    * `actual_output` - String output from the LLM to be evaluated

  ## Examples

      iex> Dantex.Eval.RegexMatchMetric.score(~r/hello/, "hello world")
      1

      iex> Dantex.Eval.RegexMatchMetric.score("hello", "goodbye")
      0
  """
  @spec score(Metric.t(), TestCase.t()) :: 0 | 1
  def score(metric, %TestCase{actual_output: actual_output}) do
    regex =
      case metric.regex do
        regex when is_binary(regex) -> Regex.compile!(regex)
        regex -> regex
      end

    case Regex.match?(regex, actual_output) do
      true -> 1
      false -> 0
    end
  end

  @doc """
  Determines if a score passes the evaluation criteria.
  For RegexMatchMetric, a score of 1 passes, 0 fails.

  ## Parameters
    * `score` - The numeric score to evaluate

  ## Examples

      iex> Dantex.Eval.RegexMatchMetric.pass(1)
      true

      iex> Dantex.Eval.RegexMatchMetric.pass(0)
      false
  """
  @spec pass(number()) :: boolean()
  def pass(1), do: true
  def pass(_), do: false

  @doc """
  Creates a new RegexMatchMetric with the provided regex pattern.
  This is a convenience function to allow for consistent handling of metrics.

  ## Parameters
    * `regex` - String or Regex pattern to use for matching

  ## Examples

      iex> metric = Dantex.Eval.RegexMatchMetric.new("hello")
      iex> metric.regex
      ~r/hello/
  """
  @spec new(Regex.t()) :: %{regex: Regex.t()}
  def new(regex) do
    %{regex: regex}
  end
end
