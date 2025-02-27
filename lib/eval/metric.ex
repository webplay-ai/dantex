defmodule Dantex.Eval.Metric do
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
