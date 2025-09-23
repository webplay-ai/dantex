defmodule Dantex.Tool.RemoteTool do
  @moduledoc """
  Wrapper for remote provider tools that don't require local implementation.

  These are tools provided directly by the AI provider (like Anthropic's web_search)
  that handle execution on the provider side rather than requiring local tool calls.

  ## Usage

      # Anthropic web search tool
      web_search = RemoteTool.new(
        type: "web_search_20250305",
        name: "web_search",
        max_uses: 5
      )

      agent = Agent.new(
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        remote_tools: [web_search]
      )
  """

  @behaviour Dantex.Tool

  @type t :: %__MODULE__{
    type: String.t(),
    name: String.t(),
    max_uses: non_neg_integer() | nil,
    description: String.t() | nil,
    metadata: map()
  }

  defstruct [
    :type,
    :name,
    :max_uses,
    :description,
    :metadata
  ]

  @doc """
  Creates a new remote tool specification.

  ## Options

    * `:type` - The remote tool type identifier (required)
    * `:name` - The tool name (required)
    * `:max_uses` - Maximum number of times the tool can be used (optional)
    * `:description` - Tool description (optional)
    * `:metadata` - Additional tool-specific metadata (optional, default: %{})

  ## Examples

      # Anthropic web search
      RemoteTool.new(
        type: "web_search_20250305",
        name: "web_search",
        max_uses: 5
      )

      # Custom remote tool with metadata
      RemoteTool.new(
        type: "custom_search_v1",
        name: "search_docs",
        description: "Search documentation",
        metadata: %{domain: "docs.example.com"}
      )
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    type = Keyword.fetch!(opts, :type)
    name = Keyword.fetch!(opts, :name)
    max_uses = Keyword.get(opts, :max_uses)
    description = Keyword.get(opts, :description)
    metadata = Keyword.get(opts, :metadata, %{})

    %__MODULE__{
      type: type,
      name: name,
      max_uses: max_uses,
      description: description,
      metadata: metadata
    }
  end

  @doc """
  Remote tools don't execute locally - they're handled by the provider.
  This function should never be called in normal operation.
  """
  @impl Dantex.Tool
  def call(_params) do
    {:error, "Remote tools are executed by the provider, not locally"}
  end

  # RemoteTool doesn't implement the standard Tool behavior since it's not a callable tool
  # These functions should not be called - they're here to satisfy the type system
  @impl Dantex.Tool
  def tool_name, do: raise("Use RemoteTool.get_name/1 instead")

  @impl Dantex.Tool
  def tool_description, do: raise("Use RemoteTool.get_description/1 instead")

  @doc """
  Gets the name of a remote tool instance.
  """
  @spec get_name(t()) :: String.t()
  def get_name(%__MODULE__{name: name}), do: name

  @doc """
  Gets the description of a remote tool instance.
  """
  @spec get_description(t()) :: String.t()
  def get_description(%__MODULE__{description: description}) when not is_nil(description), do: description
  def get_description(%__MODULE__{type: type}), do: "Remote tool: #{type}"

  @doc """
  Remote tools don't have JSON schemas since they're provider-specific.
  This function should not be called for remote tools.
  """
  def generate_tool_json_schema(%__MODULE__{}) do
    raise "Remote tools don't have JSON schemas - they're handled by the provider"
  end

  @doc """
  Converts the remote tool to the format expected by the AI provider.

  ## Parameters

    * `tool` - The remote tool instance
    * `provider` - The provider type (:anthropic, :openai, :gemini, etc.)
  """
  @spec to_provider_format(t(), atom()) :: map()
  def to_provider_format(%__MODULE__{} = tool, provider) do
    case provider do
      :anthropic ->
        base = %{
          type: tool.type,
          name: tool.name
        }

        base
        |> maybe_add_max_uses(tool.max_uses)
        |> maybe_add_description(tool.description)
        |> Map.merge(tool.metadata)

      _ ->
        # Default format for other providers (most don't support remote tools yet)
        base = %{
          type: tool.type,
          name: tool.name
        }

        base
        |> maybe_add_max_uses(tool.max_uses)
        |> maybe_add_description(tool.description)
        |> Map.merge(tool.metadata)
    end
  end

  # Backward compatibility - defaults to :anthropic
  @spec to_provider_format(t()) :: map()
  def to_provider_format(%__MODULE__{} = tool) do
    to_provider_format(tool, :anthropic)
  end

  defp maybe_add_max_uses(map, nil), do: map
  defp maybe_add_max_uses(map, max_uses), do: Map.put(map, :max_uses, max_uses)

  defp maybe_add_description(map, nil), do: map
  defp maybe_add_description(map, description), do: Map.put(map, :description, description)

  @doc """
  Checks if a tool specification is for a remote tool.
  """
  @spec remote_tool?(any()) :: boolean()
  def remote_tool?(%__MODULE__{}), do: true
  def remote_tool?(_), do: false
end