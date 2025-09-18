defmodule Dantex.Providers.Baseten do
  @moduledoc """
  Baseten provider implementation for chat completions.
  
  Uses OpenAI-compatible API endpoints with Baseten's inference platform.
  Delegates to the OpenAI provider with Baseten-specific configuration.
  """

  @behaviour Dantex.Provider

  alias Dantex.Providers.OpenAI
  alias Dantex.Message

  @spec chat_completion(map()) ::
          {:ok, list(Message.t()), Dantex.Provider.usage()}
          | {:error, String.t()}
          | {:rate_limit, String.t()}
  def chat_completion(opts) when is_map(opts) do
    baseten_config = get_baseten_config()
    
    unless baseten_config[:api_key] do
      {:error, "Baseten API key not configured"}
    end
    
    # Build options for OpenAI provider with Baseten-specific settings
    # Merge provided opts with Baseten configuration defaults
    openai_opts = Map.merge(%{
      api_key: baseten_config[:api_key],
      base_url: baseten_config[:base_url] || "https://inference.baseten.co",
      temperature: baseten_config[:temperature] || 1.0,
      top_p: baseten_config[:top_p] || 1.0,
      max_tokens: baseten_config[:max_tokens] || 8000,
      presence_penalty: baseten_config[:presence_penalty] || 0,
      frequency_penalty: baseten_config[:frequency_penalty] || 0,
      stop: baseten_config[:stop] || []
    }, opts)
    
    # Delegate to OpenAI provider with Baseten configuration
    case OpenAI.chat_completion(openai_opts) do
      {:ok, messages, usage} -> {:ok, messages, usage}
      {:error, "OpenAI Error: " <> error} -> {:error, "Baseten Error: #{error}"}
      other -> other
    end
  end

  defp get_baseten_config do
    case Application.get_env(:dantex, :providers) do
      nil -> []
      providers when is_list(providers) -> Keyword.get(providers, :baseten, [])
      providers when is_map(providers) -> Map.get(providers, :baseten, %{}) |> Map.to_list()
    end
  end
end