defmodule Dantex.Providers.Ollama do
  @moduledoc """
  Provides an interface to the Ollama LLM service.
  """
  alias Dantex.Message
  alias Dantex.Provider
  @behaviour Provider

  require Logger

  @default_api_base "http://localhost:11434"

  @doc """
  Generates content using the Ollama LLM service.

  ## Parameters

    * `model` - The model name to use (e.g., "llama2", "mistral", etc.)
    * `messages` - List of messages in the conversation

  ## Returns

  The generated content, or an error message.
  """
  @spec chat_completion(String.t(), [Message.t()]) ::
          {:ok, [Message.t()], Provider.usage()} | {:error, String.t()}
  def chat_completion(model, messages) when is_list(messages) do
    url = "#{api_base()}/api/chat"

    headers = [{"Content-Type", "application/json"}]
    body = build_request_body(model, messages)

    try do
      {:ok, %{status_code: status_code, body: body}} =
        HTTPoison.post(url, body, headers)

      case status_code do
        200 ->
          case Jason.decode(body) do
            {:ok, response} ->
              parse_response(response)

            {:error, error} ->
              Logger.error("Failed to decode JSON: #{inspect(error)}")
              {:error, "Failed to decode JSON: #{error}"}
          end

        _ ->
          Logger.error(
            "Ollama API request failed with status code: #{status_code} and body: #{body}"
          )

          {:error, "Ollama API request failed with status code: #{status_code}"}
      end
    rescue
      e ->
        Logger.error("Ollama API request failed with exception: #{inspect(e)}")
        {:error, "Ollama API request failed with exception: #{inspect(e)}"}
    end
  end

  @spec build_request_body(String.t(), [Message.t()]) :: String.t()
  defp build_request_body(model, messages) do
    formatted_messages =
      Enum.map(messages, fn %Message{role: role, content: content} ->
        %{
          role: role,
          content: content
        }
      end)

    Jason.encode!(%{
      model: model,
      messages: formatted_messages,
      stream: false
    })
  end

  @spec parse_response(map()) ::
          {:ok, [Message.t()], Provider.usage()} | {:error, String.t()}
  defp parse_response(%{"message" => %{"role" => role, "content" => content}, "eval_count" => eval_count}) do
    message = %Message{
      role: role,
      content: content
    }

    # Ollama provides eval_count which is roughly equivalent to the number of tokens generated
    # For total tokens, we make a rough estimate based on the input and output
    formatted_usage = %{
      total_tokens: eval_count
    }

    {:ok, [message], formatted_usage}
  end

  defp parse_response(%{"message" => %{"role" => role, "content" => content}}) do
    message = %Message{
      role: role,
      content: content
    }

    # When eval_count is not provided, we set tokens to 0
    formatted_usage = %{
      total_tokens: 0
    }

    {:ok, [message], formatted_usage}
  end

  defp parse_response(_), do: {:error, "Invalid response format"}

  defp api_base do
    System.get_env("OLLAMA_API_BASE") || @default_api_base
  end
end
