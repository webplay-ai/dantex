defmodule Dantex.Tool.MCP.Filter do
  @moduledoc """
  Provides filtering capabilities for MCP tools.
  
  Supports multiple filtering strategies:
  - Whitelist/blacklist by exact tool names
  - Pattern-based filtering using regex
  - Security-level based filtering
  - Configuration-based default filters
  
  ## Filter Options
  
  - `allow: [string]` - Only allow tools with these exact names
  - `block: [string]` - Block tools with these exact names  
  - `allow_patterns: [string]` - Only allow tools matching these regex patterns
  - `block_patterns: [string]` - Block tools matching these regex patterns
  - `security_level: atom` - Only allow tools up to this security level
  
  ## Usage
  
      # In agent configuration
      mcp_filters: %{
        MyApp.MCP.FileSystemClient => %{
          allow: ["read_file", "list_directory"],
          block_patterns: ["^delete_", "^format_"]
        },
        MyApp.MCP.WebSearchClient => %{
          security_level: :safe
        }
      }
      
      # In application config  
      config :dantex, :mcp_filters,
        MyApp.MCP.FileSystemClient: %{
          block: ["delete_file", "format_disk"]
        }
  """
  
  @type filter_option :: 
    {:allow, [String.t()]} |
    {:block, [String.t()]} |
    {:allow_patterns, [String.t()]} |
    {:block_patterns, [String.t()]} |
    {:security_level, atom()}
    
  @type filter_config :: %{optional(filter_option) => any()}
  
  @doc """
  Applies filters to a list of tool names.
  
  ## Parameters
  
    * `tools` - List of tool names to filter
    * `filters` - Filter configuration map
    
  ## Returns
  
    * List of filtered tool names
    
  ## Examples
  
      tools = ["read_file", "write_file", "delete_file", "list_directory"]
      
      # Whitelist filtering
      Filter.apply(tools, %{allow: ["read_file", "list_directory"]})
      # => ["read_file", "list_directory"]
      
      # Blacklist filtering  
      Filter.apply(tools, %{block: ["delete_file"]})
      # => ["read_file", "write_file", "list_directory"]
      
      # Pattern filtering
      Filter.apply(tools, %{block_patterns: ["^delete_"]})
      # => ["read_file", "write_file", "list_directory"]
  """
  @spec apply([String.t()], filter_config()) :: [String.t()]
  def apply(tools, filters) when is_list(tools) and is_map(filters) do
    tools
    |> apply_allow_filter(filters)
    |> apply_block_filter(filters)
    |> apply_pattern_filters(filters)
    |> apply_security_filter(filters)
  end
  
  def apply(tools, _), do: tools
  
  @doc """
  Merges multiple filter configurations with precedence.
  
  Later filters override earlier ones for conflicting keys.
  
  ## Parameters
  
    * `filter_configs` - List of filter configuration maps
    
  ## Returns
  
    * Merged filter configuration
    
  ## Example
  
      config_filter = %{allow: ["read_file"], block: ["delete_file"]}
      agent_filter = %{allow: ["read_file", "write_file"]}  # override
      
      Filter.merge([config_filter, agent_filter])
      # => %{allow: ["read_file", "write_file"], block: ["delete_file"]}
  """
  @spec merge([filter_config()]) :: filter_config()
  def merge(filter_configs) when is_list(filter_configs) do
    Enum.reduce(filter_configs, %{}, &Map.merge(&2, &1))
  end
  
  @doc """
  Validates a filter configuration.
  
  ## Parameters
  
    * `filters` - Filter configuration to validate
    
  ## Returns
  
    * `:ok` if valid
    * `{:error, reason}` if invalid
  """
  @spec validate(filter_config()) :: :ok | {:error, String.t()}
  def validate(filters) when is_map(filters) do
    with :ok <- validate_list_filters(filters, :allow),
         :ok <- validate_list_filters(filters, :block),
         :ok <- validate_pattern_filters(filters, :allow_patterns),
         :ok <- validate_pattern_filters(filters, :block_patterns),
         :ok <- validate_security_level(filters) do
      :ok
    end
  end
  
  def validate(_), do: {:error, "Filters must be a map"}
  
  # Private functions
  
  defp apply_allow_filter(tools, %{allow: allowed}) when is_list(allowed) do
    Enum.filter(tools, &(&1 in allowed))
  end
  
  defp apply_allow_filter(tools, _), do: tools
  
  defp apply_block_filter(tools, %{block: blocked}) when is_list(blocked) do
    Enum.reject(tools, &(&1 in blocked))
  end
  
  defp apply_block_filter(tools, _), do: tools
  
  defp apply_pattern_filters(tools, filters) do
    tools
    |> apply_allow_patterns(filters)
    |> apply_block_patterns(filters)
  end
  
  defp apply_allow_patterns(tools, %{allow_patterns: patterns}) when is_list(patterns) do
    compiled_patterns = compile_patterns(patterns)
    
    Enum.filter(tools, fn tool_name ->
      Enum.any?(compiled_patterns, fn {:ok, regex} ->
        Regex.match?(regex, tool_name)
      end)
    end)
  end
  
  defp apply_allow_patterns(tools, _), do: tools
  
  defp apply_block_patterns(tools, %{block_patterns: patterns}) when is_list(patterns) do
    compiled_patterns = compile_patterns(patterns)
    
    Enum.reject(tools, fn tool_name ->
      Enum.any?(compiled_patterns, fn {:ok, regex} ->
        Regex.match?(regex, tool_name)
      end)
    end)
  end
  
  defp apply_block_patterns(tools, _), do: tools
  
  defp apply_security_filter(tools, %{security_level: level}) do
    allowed_levels = get_allowed_security_levels(level)
    
    Enum.filter(tools, fn tool_name ->
      tool_security_level = get_tool_security_level(tool_name)
      tool_security_level in allowed_levels
    end)
  end
  
  defp apply_security_filter(tools, _), do: tools
  
  defp compile_patterns(patterns) do
    Enum.map(patterns, fn pattern ->
      case Regex.compile(pattern) do
        {:ok, regex} -> {:ok, regex}
        {:error, _} -> {:error, pattern}
      end
    end)
    |> Enum.filter(fn
      {:ok, _} -> true
      {:error, pattern} -> 
        require Logger
        Logger.warning("Invalid regex pattern: #{pattern}")
        false
    end)
  end
  
  # Security level definitions
  defp get_allowed_security_levels(:safe), do: [:safe]
  defp get_allowed_security_levels(:moderate), do: [:safe, :moderate]
  defp get_allowed_security_levels(:dangerous), do: [:safe, :moderate, :dangerous]
  defp get_allowed_security_levels(_), do: [:safe]
  
  # Tool security level mapping (configurable via application config)
  defp get_tool_security_level(tool_name) do
    security_mapping = Application.get_env(:dantex, :tool_security_levels, %{})
    Map.get(security_mapping, tool_name, :safe)  # default to safe
  end
  
  # Validation helpers
  
  defp validate_list_filters(filters, key) do
    case Map.get(filters, key) do
      nil -> :ok
      list when is_list(list) ->
        if Enum.all?(list, &is_binary/1) do
          :ok
        else
          {:error, "#{key} must be a list of strings"}
        end
      _ -> {:error, "#{key} must be a list"}
    end
  end
  
  defp validate_pattern_filters(filters, key) do
    case Map.get(filters, key) do
      nil -> :ok
      patterns when is_list(patterns) ->
        invalid_patterns = Enum.filter(patterns, fn pattern ->
          !is_binary(pattern) || match?({:error, _}, Regex.compile(pattern))
        end)
        
        if Enum.empty?(invalid_patterns) do
          :ok
        else
          {:error, "#{key} contains invalid regex patterns: #{inspect(invalid_patterns)}"}
        end
      _ -> {:error, "#{key} must be a list of regex patterns"}
    end
  end
  
  defp validate_security_level(filters) do
    case Map.get(filters, :security_level) do
      nil -> :ok
      level when level in [:safe, :moderate, :dangerous] -> :ok
      level -> {:error, "security_level must be one of [:safe, :moderate, :dangerous], got: #{inspect(level)}"}
    end
  end
end