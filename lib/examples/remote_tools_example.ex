defmodule Dantex.Examples.RemoteToolsExample do
  @moduledoc """
  Example demonstrating how to use remote provider tools alongside regular tools.

  This example shows how to combine local tools (that execute in your application)
  with remote tools (that execute on the provider side, like Anthropic's web search).
  """

  alias Dantex.{Agent, Message}
  alias Dantex.Tool.RemoteTool

  @doc """
  Example using Anthropic's web search tool.

  ## Usage

      iex> Dantex.Examples.RemoteToolsExample.run_web_search_example()
      {:ok, response, updated_agent}
  """
  def run_web_search_example do
    web_search_tool = RemoteTool.new(
      type: "web_search_20250305",
      name: "web_search",
      max_uses: 5
    )

    agent = Agent.new(
      provider: :anthropic,
      model: "claude-3-5-sonnet-20241022",
      messages: [
        Message.system("You are a helpful assistant that can search the web.")
      ],
      tools: [
        web_search_tool
      ]
    )

    Agent.run(agent, "Search for recent news about TypeScript 5.5")
  end
end
