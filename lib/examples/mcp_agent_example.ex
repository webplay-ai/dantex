defmodule Dantex.Examples.MCPAgentExample do
  @moduledoc """
  Example showing how to use MCP (Model Context Protocol) tools with Dantex agents.

  This example demonstrates:
  - Setting up MCP clients
  - Configuring tool filtering
  - Using MCP tools alongside local tools
  - Best practices for security and configuration
  """

  alias Dantex.{Agent, Message}
  alias Dantex.Examples.MCP.{FileSystemClient, WebSearchClient}
  alias Dantex.Examples.CalculatorTool

  @doc """
  Creates an agent with both local and MCP tools.

  ## Example Usage

      # Start your MCP servers first (see setup instructions in client modules)

      # Create agent with mixed tools
      {:ok, agent} = MCPAgentExample.create_mixed_agent()

      # Ask the agent to use both local and MCP tools
      {:ok, response, agent} = Agent.run(agent, "Calculate 2+2 and then search for 'Elixir programming' online")
  """
  def create_mixed_agent do
    try do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [
          Message.system("""
          You are a helpful assistant with access to calculation, filesystem, and web search tools.

          Available capabilities:
          - Perform mathematical calculations
          - Read and list files and directories
          - Search the web for information

          Always be helpful and use the appropriate tools to answer user questions.
          """)
        ],
        tools: [CalculatorTool],  # Local Dantex tool
        mcp_clients: [FileSystemClient, WebSearchClient],  # MCP tools
        mcp_filters: %{
          FileSystemClient => %{
            # Only allow safe read operations
            allow: ["read_file", "list_directory", "get_file_info"],
            block: ["write_file", "delete_file", "create_directory"]
          },
          WebSearchClient => %{
            # Allow search but be careful with sensitive operations
            allow: ["web_search"],
            block_patterns: ["^admin_", "^delete_"]
          }
        }
      )

      {:ok, agent}
    rescue
      error ->
        {:error, "Failed to create MCP agent: #{Exception.message(error)}"}
    end
  end

  @doc """
  Creates an agent with only filesystem tools and security filtering.
  """
  def create_filesystem_agent do
    Agent.new(
      provider: :openai,
      model: "gpt-4o-mini",
      messages: [
        Message.system("You are a file management assistant. You can read files and list directories, but cannot modify the filesystem.")
      ],
      mcp_clients: [FileSystemClient],
      mcp_filters: %{
        FileSystemClient => %{
          # Very restrictive - only read operations
          allow: ["read_file", "list_directory", "search_files", "get_file_info"],
          security_level: :safe
        }
      }
    )
  end

  @doc """
  Creates an agent with pattern-based filtering.
  """
  def create_pattern_filtered_agent do
    Agent.new(
      provider: :openai,
      model: "gpt-4o-mini",
      messages: [Message.system("You have access to various tools with pattern-based filtering.")],
      mcp_clients: [FileSystemClient, WebSearchClient],
      mcp_filters: %{
        FileSystemClient => %{
          # Allow read operations, block anything dangerous
          allow_patterns: ["^read_", "^list_", "^get_", "^search_"],
          block_patterns: ["^write_", "^delete_", "^create_", "^modify_"]
        },
        WebSearchClient => %{
          # Allow search operations
          allow_patterns: ["^search", "^web_"],
          block_patterns: ["^admin", "^delete", "^modify"]
        }
      }
    )
  end

  @doc """
  Example of adding MCP tools to an existing agent.
  """
  def add_mcp_tools_example do
    # Start with a basic agent
    agent = Agent.new(
      provider: :openai,
      model: "gpt-4o-mini",
      mcp_clients: [FileSystemClient],
      mcp_filters: %{
        FileSystemClient => %{
          allow: ["read_file", "list_directory", "search_files", "get_file_info"],
        }
      },
      tools: [CalculatorTool]
    )

    agent
  end

  @doc """
  Run an interactive example session.
  """
  def run_example do
    case create_mixed_agent() do
      {:ok, agent} ->
        IO.puts("🤖 MCP Agent created successfully!")
        IO.puts("Available tools: #{inspect(Enum.map(agent.tools, &tool_name/1))}")

        # Example interactions
        examples = [
          "What is 15 * 23?",
          "List the files in the current directory",
          "Search for 'Elixir MCP protocol' online"
        ]

        Enum.reduce(examples, agent, fn prompt, acc_agent ->
          IO.puts("\n📝 User: #{prompt}")

          case Agent.run(acc_agent, prompt) do
            {:ok, response, new_agent} ->
              IO.puts("🤖 Assistant: #{response.content}")
              new_agent

            {:error, error} ->
              IO.puts("❌ Error: #{inspect(error)}")
              acc_agent
          end
        end)

      {:error, error} ->
        IO.puts("❌ Failed to create agent: #{error}")
        IO.puts("Make sure your MCP servers are running!")
    end
  end

  # Helper to get tool name safely
  defp tool_name(tool) do
    if function_exported?(tool, :tool_name, 0) do
      tool.tool_name()
    else
      inspect(tool)
    end
  end
end
