defmodule Dantex.Message do
  @moduledoc """
  Message structure for AI conversations.
  
  Defines types and constructor functions for different message roles (system, user, assistant, tool)
  and handles tool calls and tool results in the conversation flow.
  """
  @type tool_call_function :: %{
          name: String.t(),
          arguments: String.t() # JSON-encoded string
        }

  @type tool_call :: %{
          id: String.t(),
          type: String.t(), # Currently always "function"
          function: tool_call_function
        }

  @type t :: %__MODULE__{
          role: String.t(),
          content: String.t() | nil,
          tool_calls: list(tool_call) | nil,
          tool_call_id: String.t() | nil,
        }

  @derive Jason.Encoder
  defstruct [:role, :content, :tool_calls, :tool_call_id]

  @spec system(String.t()) :: t()
  def system(message) do
    %__MODULE__{
      role: "system",
      content: message
    }
  end

  @spec user(String.t()) :: t()
  def user(message) do
    %__MODULE__{
      role: "user",
      content: message
    }
  end

  @spec assistant(String.t()) :: t()
  def assistant(message) do
    %__MODULE__{
      role: "assistant",
      content: message
    }
  end

  @spec tool_call(String.t(), String.t(), map()) :: t()
  def tool_call(tool_call_id, name, arguments) do
    %__MODULE__{
      role: "assistant",
      content: nil,
      tool_calls: [
        %{
          id: tool_call_id,
          type: "function",
          function: %{
            name: name,
            arguments: Jason.encode!(arguments)
          }
        }
      ]
    }
  end

  @spec tool_result(String.t(), any()) :: t()
  def tool_result(tool_call_id, result) do
    %__MODULE__{
      role: "tool",
      tool_call_id: tool_call_id,
      content: Jason.encode!(result)
    }
  end

  @doc """
  Converts a message to a telemetry-safe map.
  
  Returns a plain map that can be safely used with Access behavior and
  doesn't expose internal struct implementation details.
  """
  @spec to_telemetry(t()) :: map()
  def to_telemetry(%__MODULE__{} = message) do
    %{
      role: message.role,
      content: message.content,
      has_tool_calls: not is_nil(message.tool_calls) and length(message.tool_calls) > 0,
      tool_calls_count: if(message.tool_calls, do: length(message.tool_calls), else: 0),
      tool_calls: message.tool_calls,
      tool_call_id: message.tool_call_id
    }
  end
end
