defmodule Dantex.Examples.MCP.WebSearchClient do
  @moduledoc """
  Example MCP client for web search operations using Brave Search.
  
  This client connects to the @modelcontextprotocol/server-brave-search MCP server
  which provides web search capabilities.
  
  ## Setup
  
  1. Install the MCP server:
     ```bash
     npm install -g @modelcontextprotocol/server-brave-search
     ```
  
  2. Set up your Brave Search API key:
     ```bash
     export BRAVE_API_KEY="your_brave_api_key"
     ```
  
  3. Add to your supervision tree:
     ```elixir
     children = [
       {Dantex.Examples.MCP.WebSearchClient,
        transport: {:stdio, command: "npx", args: ["@modelcontextprotocol/server-brave-search"]}}
     ]
     ```
  
  4. Use in agent:
     ```elixir
     agent = Dantex.Agent.new(
       provider: :openai,
       model: "gpt-4o-mini",
       mcp_clients: [Dantex.Examples.MCP.WebSearchClient],
       mcp_filters: %{
         Dantex.Examples.MCP.WebSearchClient => %{
           allow: ["web_search", "search_images"]
         }
       }
     )
     ```
  
  ## Available Tools
  
  - `web_search` - Perform web search and get results
  - `search_images` - Search for images
  - `get_page_content` - Extract content from a web page
  """
  
  use Hermes.Client,
    name: "DantexWebSearchClient",
    version: "1.0.0",
    protocol_version: "2024-11-05",
    capabilities: []
end