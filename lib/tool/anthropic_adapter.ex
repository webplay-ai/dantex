defmodule Dantex.Tool.AnthropicAdapter do
  @moduledoc """
  Anthropic-compatible tool adapter.
  
  This adapter is a pass-through implementation similar to OpenAIAdapter since 
  the Anthropic provider already converts tool calls to OpenAI-compatible format
  during response parsing. This ensures compatibility with the existing tool
  execution pipeline.
  """
  alias Dantex.{Message, Tool}

  @behaviour Dantex.Tool.ToolAdapter

  @doc """
  Extracts function calls from Anthropic-formatted response content.
  For Anthropic, the function calls are already structured in the OpenAI-compatible
  format by the provider's parse_response function, so this function simply passes them through.

  ## Examples

      iex> message = %Message{tool_calls: [%{id: "toolu_123", type: "function", function: %{name: "get_weather", arguments: "{\"location\":\"San Francisco\"}"}}]}
      iex> Dantex.Tool.AnthropicAdapter.extract_tool_calls(message)
      {:ok, [%{id: "toolu_123", type: "function", function: %{name: "get_weather", arguments: "{\"location\":\"San Francisco\"}"}}]}
  """
  @spec extract_tool_calls(Message.t()) :: {:ok, Message.t()} | {:error, term()}
  def extract_tool_calls(%Message{content: _content} = message) do
    # This is a no-op since the Anthropic provider already converts
    # tool calls to OpenAI-compatible format during response parsing
    {:ok, message}
  end

  # Catch-all clause for compatibility
  def extract_tool_calls(msg), do: {:ok, msg}

  @doc """
  Builds documentation for a list of tools.
  This is a no-op implementation for Anthropic compatibility with XMLAdapter.

  ## Examples

      iex> tools = [Dantex.Examples.WeatherTool]
      iex> Dantex.Tool.AnthropicAdapter.build_tool_docs(tools)
      ""
  """
  @spec build_tool_docs(list(Tool.t())) :: String.t()
  def build_tool_docs(_tools) do
    ""
  end
end