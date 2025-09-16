defmodule Dantex.Tool.MCP do
  @moduledoc """
  MCP (Model Context Protocol) tool wrapper for Dantex.
  
  This module wraps MCP server tools to make them compatible with the Dantex.Tool behavior,
  allowing seamless integration of MCP tools alongside local Dantex tools.
  
  ## Usage
  
      # Create an MCP tool from a client and tool name
      mcp_tool = Dantex.Tool.MCP.new(MyApp.MCP.FileSystemClient, "read_file")
      
      # Use in agent alongside regular tools
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        tools: [MyLocalTool, mcp_tool]
      )
  """
  
  alias Dantex.Tool.MCP.SchemaConverter
  require Logger
  
  @doc """
  Creates a new MCP tool wrapper module from an MCP client and tool name.
  
  This generates a dynamic module that implements the Dantex.Tool behavior
  and can be used directly with agents.
  
  ## Parameters
  
    * `client_module` - The MCP client module that implements Hermes.Client
    * `tool_name` - The name of the tool as reported by the MCP server
    
  ## Returns
  
    * `{:ok, module}` - Successfully created MCP tool module
    * `{:error, reason}` - Failed to create wrapper (tool not found, client not available, etc.)
    
  ## Example
  
      {:ok, mcp_tool_module} = Dantex.Tool.MCP.new(MyApp.MCP.FileSystemClient, "read_file")
      
      # Use in agent
      agent = Agent.new(tools: [mcp_tool_module])
  """
  def new(client_module, tool_name) when is_atom(client_module) and is_binary(tool_name) do
    case get_tool_definition(client_module, tool_name) do
      {:ok, tool_def} ->
        create_mcp_tool_module(client_module, tool_name, tool_def)
        
      {:error, reason} ->
        Logger.warning("Failed to create MCP tool #{tool_name} from #{client_module}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Same as new/2 but raises on error.
  """
  def new!(client_module, tool_name) do
    case new(client_module, tool_name) do
      {:ok, mcp_tool_module} -> mcp_tool_module
      {:error, reason} -> raise "Failed to create MCP tool: #{inspect(reason)}"
    end
  end
  
  # Creates a dynamic module that implements Dantex.Tool for an MCP tool
  defp create_mcp_tool_module(client_module, tool_name, tool_def) do
    module_name = create_module_name(client_module, tool_name)
    description = tool_def["description"] || ""
    input_schema = SchemaConverter.convert_json_schema_to_ecto(tool_name, tool_def["inputSchema"])
    
    try do
      Module.create(module_name, quote do
        @behaviour Dantex.Tool
        
        @client_module unquote(client_module)
        @tool_name unquote(tool_name)
        @tool_description unquote(description)
        @input_schema unquote(input_schema)
        
        require Logger
        
        @impl Dantex.Tool
        def call(params) when is_map(params) do
          # Extract context and actual parameters
          _context = Map.get(params, :context, %{})
          tool_params = Map.drop(params, [:context])
          
          Logger.debug("Calling MCP tool #{@tool_name} with params: #{inspect(tool_params)}")
          
          case @client_module.call_tool(@tool_name, tool_params) do
            {:ok, result} ->
              Logger.debug("MCP tool #{@tool_name} returned: #{inspect(result)}")
              {:ok, result}
              
            {:error, reason} ->
              Logger.error("MCP tool #{@tool_name} failed: #{inspect(reason)}")
              {:error, reason}
          end
        rescue
          error ->
            Logger.error("Exception in MCP tool #{@tool_name}: #{Exception.message(error)}")
            {:error, Exception.message(error)}
        end
        
        @impl Dantex.Tool
        def tool_name, do: @tool_name
        
        @impl Dantex.Tool
        def tool_description, do: @tool_description
        
        # For compatibility with existing validation code
        def __input_schema__, do: @input_schema
      end, Macro.Env.location(__ENV__))
      
      {:ok, module_name}
    rescue
      error ->
        {:error, "Failed to create MCP tool module: #{Exception.message(error)}"}
    end
  end
  
  # Create a unique module name for an MCP tool
  defp create_module_name(client_module, tool_name) do
    client_name = client_module |> Module.split() |> List.last()
    sanitized_tool_name = 
      tool_name
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> Macro.camelize()
    
    Module.concat([Dantex.Tool.MCP.Generated, "#{client_name}_#{sanitized_tool_name}"])
  end
  
  @doc """
  Lists all available tools from an MCP client.

  This function follows proper MCP capability discovery by first checking
  server capabilities before attempting to list tools.
  
  ## Parameters
  
    * `client_module` - The MCP client module
    
  ## Returns
  
    * `{:ok, [tool_name]}` - List of available tool names
    * `{:error, reason}` - Failed to list tools
  """
  def list_tools(client_module) when is_atom(client_module) do
    with {:ok, capabilities} <- get_server_capabilities(client_module),
         {:ok, true} <- check_tools_capability(capabilities),
         {:ok, tools} <- fetch_tools(client_module) do
      tool_names = extract_tool_names(tools)
      {:ok, tool_names}
    else
      {:ok, false} ->
        Logger.info("MCP server #{client_module} does not support tools")
        {:ok, []}
        
      {:error, reason} ->
        Logger.warning("Failed to list tools from #{client_module}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Get server capabilities using proper MCP flow
  defp get_server_capabilities(client_module) do
    try do
      case client_module.get_server_capabilities() do
        {:ok, capabilities} -> {:ok, capabilities}
        {:error, reason} -> {:error, reason}
        capabilities when is_map(capabilities) -> {:ok, capabilities}
        _ -> {:error, :capabilities_unavailable}
      end
    rescue
      error ->
        Logger.warning("Cannot get capabilities from #{client_module}: #{Exception.message(error)}")
        {:error, Exception.message(error)}
    end
  end

  # Check if server supports tools capability
  defp check_tools_capability(capabilities) do
    tools_supported = 
      case capabilities do
        %{"tools" => _} -> true
        %{tools: _} -> true
        _ -> false
      end
    
    {:ok, tools_supported}
  end

  # Fetch tools from server
  defp fetch_tools(client_module) do
    try do
      case client_module.list_tools() do
        {:ok, %{"result" => %{"tools" => tools}}} when is_list(tools) ->
          {:ok, tools}
          
        {:ok, tools} when is_list(tools) ->
          {:ok, tools}
          
        {:error, reason} ->
          {:error, reason}
          
        other ->
          Logger.warning("Unexpected response from #{client_module}.list_tools(): #{inspect(other)}")
          {:error, :unexpected_response}
      end
    rescue
      error ->
        Logger.error("Exception listing tools from #{client_module}: #{Exception.message(error)}")
        {:error, Exception.message(error)}
    end
  end

  # Extract tool names from various response formats
  defp extract_tool_names(tools) do
    Enum.map(tools, fn
      %{"name" => name} -> name
      name when is_binary(name) -> name
      tool -> tool["name"] || "unknown"
    end)
  end
  
  @doc """
  Creates MCP tool modules for all available tools from a client.
  
  ## Parameters
  
    * `client_module` - The MCP client module
    * `filters` - Optional filtering options (see Dantex.Tool.MCP.Filter)
    
  ## Returns
  
    * `{:ok, [module()]}` - List of MCP tool modules
    * `{:error, reason}` - Failed to discover tools
  """
  def discover_tools(client_module, filters \\ %{}) do
    with {:ok, tool_names} <- list_tools(client_module) do
      filtered_names = apply_filters(tool_names, filters)
      
      tools = Enum.reduce(filtered_names, [], fn tool_name, acc ->
        case new(client_module, tool_name) do
          {:ok, mcp_tool_module} -> [mcp_tool_module | acc]
          {:error, reason} ->
            Logger.warning("Skipping tool #{tool_name}: #{inspect(reason)}")
            acc
        end
      end)
      
      {:ok, Enum.reverse(tools)}
    end
  end
  
  # Private functions
  
  defp get_tool_definition(client_module, tool_name) do
    try do
      case client_module.get_tool(tool_name) do
        {:ok, tool_def} -> {:ok, tool_def}
        {:error, reason} -> {:error, reason}
        tool_def when is_map(tool_def) -> {:ok, tool_def}
        _ -> {:error, :tool_not_found}
      end
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end
  
  defp apply_filters(tools, %{allow: allowed}) when is_list(allowed) do
    Enum.filter(tools, &(&1 in allowed))
  end
  
  defp apply_filters(tools, %{block: blocked}) when is_list(blocked) do
    Enum.reject(tools, &(&1 in blocked))
  end
  
  defp apply_filters(tools, %{allow: allowed, block: blocked}) do
    tools
    |> apply_filters(%{allow: allowed})
    |> apply_filters(%{block: blocked})
  end
  
  defp apply_filters(tools, %{allow_patterns: patterns}) when is_list(patterns) do
    compiled_patterns = Enum.map(patterns, &Regex.compile!/1)
    
    Enum.filter(tools, fn tool_name ->
      Enum.any?(compiled_patterns, &Regex.match?(&1, tool_name))
    end)
  end
  
  defp apply_filters(tools, %{block_patterns: patterns}) when is_list(patterns) do
    compiled_patterns = Enum.map(patterns, &Regex.compile!/1)
    
    Enum.reject(tools, fn tool_name ->
      Enum.any?(compiled_patterns, &Regex.match?(&1, tool_name))
    end)
  end
  
  defp apply_filters(tools, _), do: tools
end