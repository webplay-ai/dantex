defmodule Dantex.Tool.OpenAIAdapter do
  @moduledoc """
  OpenAI-compatible tool adapter.
  
  This adapter is a pass-through implementation since OpenAI responses already
  contain properly structured tool calls that don't require additional parsing.
  """
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
  def extract_tool_calls(%Message{content: _content} = message) do
    # This is a no-op since OpenAI already parses this in the response
    {:ok, message}
  end

  # Catch-all clause for compatibility with XMLAdapter
  def extract_tool_calls(msg), do: {:ok, msg}

  @doc """
  Builds documentation for a list of tools.
  This is a no-op implementation for OpenAI compatibility with XMLAdapter.

  ## Examples

      iex> tools = [Dantex.Examples.WeatherTool]
      iex> Dantex.Tool.OpenAIAdapter.build_tool_docs(tools)
      ""
  """
  @spec build_tool_docs(list(Tool.t())) :: String.t()
  def build_tool_docs(_tools) do
    ""
  end
end
