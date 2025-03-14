defmodule Dantex.Tool.ToolHistory do
  @moduledoc """
  Tracks tool call history.
  """
  defstruct [
    :tool_name,
    :input_parameters,
    :output,
    :timestamp
  ]

  @type t :: %__MODULE__{
          tool_name: String.t(),
          input_parameters: map(),
          output: any(),
          timestamp: DateTime.t()
        }
end
