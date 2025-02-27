defmodule Dantex.Providers.Gemini do
  @moduledoc """
  Provides an interface to the Gemini LLM.
  """
  alias Dantex.Message
  alias Dantex.Provider
  @behaviour Provider

  require Logger
  @api_key System.get_env("GEMINI_API_KEY")

  @doc """
  Generates content using the Gemini LLM.

  ## Parameters

    * `prompt` - The prompt to send to the LLM.

  ## Returns

  The generated content, or an error message.
  """
  @spec chat_completion(String.t(), [Message.t()]) ::
          {:ok, [Message.t()], Provider.usage()} | {:error, String.t()}
  def chat_completion(model, messages) when is_list(messages) do
    model = "gemini-2.0-flash"

    url =
      "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{@api_key}"

    headers = [{"Content-Type", "application/json"}]
    body = build_request_body(messages)

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
            "Gemini API request failed with status code: #{status_code} and body: #{body}"
          )

          {:error, "Gemini API request failed with status code: #{status_code}"}
      end
    rescue
      e ->
        Logger.error("Gemini API request failed with exception: #{inspect(e)}")
        {:error, "Gemini API request failed with exception: #{inspect(e)}"}
    end
  end

  @spec build_request_body([Message.t()]) :: String.t()
  defp build_request_body(messages) do
    contents =
      Enum.map(messages, fn %Message{role: role, content: content} ->
        %{
          role: build_role(role),
          parts: [%{text: content}]
        }
      end)

    Jason.encode!(%{contents: contents})
  end

  # Gemini does not support the system role, but the model role only
  defp build_role("system"), do: "model"
  defp build_role(role), do: role

  @spec parse_response(map()) ::
          {:ok, [Message.t()], Provider.usage()} | {:error, String.t()}
  defp parse_response(%{"candidates" => candidates, "usageMetadata" => usage_metadata}) do
    messages =
      candidates
      |> Enum.map(fn candidate ->
        text =
          candidate
          |> Map.get("content", %{})
          |> Map.get("parts", [])
          |> List.first(%{})
          |> Map.get("text", "")

        %Message{
          role: "assistant",
          content: text
        }
      end)

    # Format usage to match our Provider.usage type
    formatted_usage = %{
      total_tokens: usage_metadata["totalTokenCount"]
    }

    {:ok, messages, formatted_usage}
  end

  # Handle case where usageMetadata is not present
  defp parse_response(%{"candidates" => candidates}) do
    messages =
      candidates
      |> Enum.map(fn candidate ->
        text =
          candidate
          |> Map.get("content", %{})
          |> Map.get("parts", [])
          |> List.first(%{})
          |> Map.get("text", "")

        %Message{
          role: "assistant",
          content: text
        }
      end)

    # Provide a default usage estimate when actual usage is not available
    estimated_usage = %{
      # We don't have enough information to make a good estimate
      total_tokens: 0
    }

    {:ok, messages, estimated_usage}
  end

  defp parse_response(_), do: {:error, "Invalid response format"}
end
