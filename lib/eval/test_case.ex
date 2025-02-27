defmodule Dantex.Eval.TestCase do
  @moduledoc """
  Defines a structure for test cases used in LLM evaluation.
  A TestCase contains input messages, expected output, and actual output.
  """

  alias Dantex.Message

  @type t :: %__MODULE__{
          input: [Message.t()],
          expected_output: String.t() | nil,
          actual_output: String.t() | nil,
          tokens: number() | nil,
          score: number() | nil,
          pass: boolean() | nil
        }

  @type result :: %{
          actual_output: String.t(),
          tokens: number(),
          score: number(),
          pass: boolean()
        }

  defstruct input: [],
            expected_output: nil,
            actual_output: nil,
            tokens: nil,
            score: nil,
            pass: nil

  @doc """
  Creates a new TestCase with the given input, expected output, and actual output.

  ## Examples

      iex> input = [Dantex.Message.user("What is 2+2?")]
      iex> Dantex.Eval.TestCase.new(input, "4", nil)
      %Dantex.Eval.TestCase{input: [%Dantex.Message{role: "user", content: "What is 2+2?"}], expected_output: "4", actual_output: nil}
  """
  @spec new([Message.t()], String.t() | nil, String.t() | nil) :: t()
  def new(input, expected_output \\ nil, actual_output \\ nil) do
    %__MODULE__{
      input: input,
      expected_output: expected_output,
      actual_output: actual_output,
      tokens: nil,
      score: nil,
      pass: nil
    }
  end

  @doc """
  Updates a TestCase with the result from an LLM evaluation.

  ## Examples

      iex> test_case = Dantex.Eval.TestCase.new([Dantex.Message.user("What is 2+2?")], "4")
      iex> result = %{actual_output: "4", tokens: 10, score: 1.0, pass: true}
      iex> Dantex.Eval.TestCase.set_result(test_case, result)
      %Dantex.Eval.TestCase{input: [%Dantex.Message{role: "user", content: "What is 2+2?"}], expected_output: "4", actual_output: "4", tokens: 10, score: 1.0, pass: true}
  """
  @spec set_result(t(), result()) :: t()
  def set_result(test_case, result) do
    %__MODULE__{
      test_case
      | actual_output: result.actual_output,
        tokens: result.tokens,
        score: result.score,
        pass: result.pass
    }
  end
end
