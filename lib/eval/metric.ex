defmodule Dantex.Eval.Metric do
  @moduledoc """
  Behaviour for evaluation metrics in the testing framework.
  
  Defines the interface for scoring and pass/fail evaluation of test cases.
  Metrics should implement `score/2` to calculate a numerical score and
  `pass/1` to determine if a score meets the passing criteria.
  """
  alias Dantex.Eval.TestCase

  @doc """
  Defines the behaviour for evaluation metrics.
  """
  @callback score(t(), TestCase.t()) :: number()

  @doc """
  Determines whether a score passes the evaluation criteria.
  """
  @callback pass(number()) :: boolean()

  @typedoc """
  Type that represents a module implementing the Metric behaviour.
  """
  @type t :: module()
end
