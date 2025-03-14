defmodule Dantex.Tool.OpenAIAdapter do
  alias Dantex.{Message, Tool}

  @behaviour Dantex.Tool.ToolAdapter

  @doc """
  Extracts function calls from OpenAI-formatted response content.
  For OpenAI, the function calls are already structured in the message's tool_calls field,
  so this function simply passes them through.

  ## Examples

      iex> message = %Message{tool_calls: [%{id: "call_123", type: "function", function: %{name: "get_weather", arguments: "{\"location\":\"San Francisco\"}"}}]}
      iex> Dantex.Tool.OpenAIAdapter.extract_tool_calls(message)
      {:ok, [%{id: "call_123", type: "function", function: %{name: "get_weather", arguments: "{\"location\":\"San Francisco\"}"}}]}
  """
  @spec extract_tool_calls(Message.t()) :: {:ok, Message.t()} | {:error, term()}
  def extract_tool_calls(message) do
    # This is a no-op since OpenAI already parses this in the response
    {:ok, message}
  end

end
