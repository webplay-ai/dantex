defmodule Dantex.Model do
  @moduledoc """
  Dantex Model abstracts model specific logic, like chat_completion, parsing the response, etc.
  """

  alias Dantex.Message
  alias Dantex.Provider
  alias Dantex.Tool
  require Logger

  @type t :: %__MODULE__{
          provider: Provider.t(),
          model: String.t()
        }

  defstruct [:provider, :model]

  @spec new({atom(), String.t()} | atom() | t(), String.t() | nil) :: t()
  def new(%__MODULE__{} = model, _model_name = nil), do: model

  def new(provider_key, model_name) when is_atom(provider_key) and is_binary(model_name) do
    provider_module = get_provider(provider_key)

    # Check if the provider is configured
    case Application.get_env(:dantex, :providers) do
      nil ->
        raise "No providers configured. Please configure at least one provider in your application's config.exs."

      providers when is_list(providers) ->
        unless Keyword.has_key?(providers, provider_key) do
          raise "Provider #{provider_key} not configured. Please configure it in your application's config.exs."
        end

      providers when is_map(providers) ->
        unless Map.has_key?(providers, provider_key) do
          raise "Provider #{provider_key} not configured. Please configure it in your application's config.exs."
        end
    end

    %__MODULE__{
      provider: provider_module,
      model: model_name
    }
  end

  def new({provider_key, model_name}, _model_name = nil)
      when is_atom(provider_key) and is_binary(model_name) do
    new(provider_key, model_name)
  end

  defp get_provider(provider_key) do
    case provider_key do
      :openai -> Dantex.Providers.OpenAI
      :ollama -> Dantex.Providers.Ollama
      :gemini -> Dantex.Providers.Gemini
      :anthropic -> Dantex.Providers.Anthropic
      :baseten -> Dantex.Providers.Baseten
      _ -> raise "Unknown provider: #{provider_key}"
    end
  end

  @doc """
  If a response_format is in form of JSON schema defintion or Ecto schema, we try to parse the response against this schema and return a map
  """
  @spec json(String.t()) :: {:ok, map()} | {:error, String.t()}
  def json(response) do
    case Jason.decode(response, keys: :atoms) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, error} ->
        Logger.error(
          "Failed to decode JSON: #{inspect(error, pretty: true)}\nContent: #{inspect(response, pretty: true)}"
        )

        {:error, "Invalid JSON response from OpenAI"}
    end
  end

  @doc """
  Sends messages to the provider for chat completion.
  Uses the provider stored in the model struct instance.
  """
  @spec chat_completion(%__MODULE__{}, list(Message.t()), list(Tool.t())) ::
          {:ok, {Message.t(), [Message.t()]}, Provider.usage()} | {:error, String.t()}
  def chat_completion(%__MODULE__{provider: provider, model: model} = _model, messages, tools)
      when not is_nil(provider) do
    opts = %{
      model: model,
      messages: messages,
      tools: tools
    }
    
    case provider.chat_completion(opts) do
      {:ok, messages, usage} when is_list(messages) ->
        last_message = List.last(messages)
        {:ok, {last_message, messages}, usage}

      response ->
        response
    end
  end

  def chat_completion(%__MODULE__{provider: nil}, _messages) do
    {:error, :no_provider_configured}
  end
end
