defmodule Dantex.Examples.MCP.FileSystemClient do
  @moduledoc """
  Example MCP client for filesystem operations.
  
  This client connects to the @modelcontextprotocol/server-filesystem MCP server
  which provides tools for reading files, listing directories, and basic file operations.
  
  ## Setup
  
  1. Install the MCP server:
     ```bash
     npm install -g @modelcontextprotocol/server-filesystem
     ```
  
  2. Add to your supervision tree:
     ```elixir
     children = [
       {Dantex.Examples.MCP.FileSystemClient,
        transport: {:stdio, command: "npx", args: ["@modelcontextprotocol/server-filesystem", "/workspace"]}}
     ]
     ```
  
  3. Use in agent:
     ```elixir
     agent = Dantex.Agent.new(
       provider: :openai,
       model: "gpt-4o-mini",
       mcp_clients: [Dantex.Examples.MCP.FileSystemClient],
       mcp_filters: %{
         Dantex.Examples.MCP.FileSystemClient => %{
           allow: ["read_file", "list_directory", "search_files"]
         }
       }
     )
     ```
  
  ## Available Tools
  
  - `read_file` - Read contents of a file
  - `write_file` - Write content to a file  
  - `list_directory` - List files and directories
  - `create_directory` - Create a new directory
  - `search_files` - Search for files matching patterns
  - `get_file_info` - Get metadata about a file
  """
  
  use Hermes.Client,
    name: "DantexFileSystemClient",
    version: "1.0.0",
    protocol_version: "2024-11-05",
    capabilities: []
end