defmodule Dantex.Providers.Moonshot do
  @moduledoc """
  Moonshot AI provider implementation for chat completions.

  This provider reuses the OpenAI implementation since Moonshot AI uses an OpenAI-compatible API.
  The only difference is the base URL configuration.
  """

  @behaviour Dantex.Provider

  @default_base_url "https://api.moonshot.ai/v1"

  @spec chat_completion(map()) ::
          {:ok, list(Dantex.Message.t()), Dantex.Provider.usage()}
          | {:error, String.t()}
          | {:rate_limit, String.t()}
  def chat_completion(opts) when is_map(opts) do
    opts = Map.put_new(opts, :base_url, @default_base_url)
    opts = Map.put_new(opts, :api_key, Dantex.Providers.Config.get_api_key(:moonshot))
    Dantex.Providers.OpenAI.chat_completion(opts)
  end
end
