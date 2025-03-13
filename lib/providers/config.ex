defmodule Dantex.Providers.Config do
  @moduledoc """
  Provides configuration functions for Dantex providers.
  """

  def get_api_key(provider) do
    get_config_value(provider, :api_key)
  end

  def get_config_value(provider, key) do
    case Application.get_env(:dantex, :providers) do
      nil ->
        # No providers configured
        nil

      providers ->
        case Keyword.get(providers, provider) do
          nil ->
            # Provider not configured
            nil

        config ->
          Map.get(config, key)
      end
    end
  end
end
