defmodule Dantex.Providers.Baseten do
  @moduledoc """
  Baseten provider implementation for chat completions.

  Direct HTTP implementation for Baseten's OpenAI-compatible API endpoints
  with custom error handling and response parsing.
  """

  @behaviour Dantex.Provider

  require Logger
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

    model = Map.get(opts, :model)
    messages = Map.get(opts, :messages, [])
    tools = Map.get(opts, :tools, [])
    timeout = Map.get(opts, :timeout, 180_000)

    api_key = baseten_config[:api_key]
    base_url = baseten_config[:base_url] || "https://inference.baseten.co"

    # Build request payload
    payload = %{
      model: model,
      messages: format_messages(messages),
      temperature: Map.get(opts, :temperature, baseten_config[:temperature] || 1.0),
      max_tokens: Map.get(opts, :max_tokens, baseten_config[:max_tokens] || 8000),
      top_p: Map.get(opts, :top_p, baseten_config[:top_p] || 1.0),
      presence_penalty: Map.get(opts, :presence_penalty, baseten_config[:presence_penalty] || 0),
      frequency_penalty:
        Map.get(opts, :frequency_penalty, baseten_config[:frequency_penalty] || 0),
      stop: Map.get(opts, :stop, baseten_config[:stop] || [])
    }

    # Add tools if provided
    payload =
      if Enum.empty?(tools) do
        payload
      else
        Map.put(payload, :tools, format_tools(tools))
      end

    # Make HTTP request
    headers = [
      {"Authorization", "Api-Key #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    url = "#{base_url}/v1/chat/completions"

    case HTTPoison.post(url, Jason.encode!(payload), headers, timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_success_response(body)

      {:ok, %HTTPoison.Response{status_code: 429, body: body}} ->
        parse_rate_limit_response(body)

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        parse_error_response(status_code, body)

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Baseten HTTP Error: #{inspect(reason)}"}
    end
  end

  @spec format_messages([Message.t()]) :: list(map())
  defp format_messages(messages) do
    Enum.map(messages, fn message ->
      case message do
        %{role: role, content: content, tool_calls: tool_calls} when not is_nil(tool_calls) ->
          %{role: role, content: content, tool_calls: tool_calls}

        %{role: role, content: content, tool_call_id: tool_call_id}
        when not is_nil(tool_call_id) ->
          %{role: role, content: content, tool_call_id: tool_call_id}

        %{role: role, content: content} ->
          %{role: role, content: content}
      end
    end)
  end

  @spec format_tools([Dantex.Tool.t()]) :: list(map())
  defp format_tools(tools) do
    Enum.map(tools, fn tool ->
      Jason.decode!(tool.generate_tool_json_schema())
    end)
  end

  defp parse_success_response(body) do
    case Jason.decode(body) do
      {:ok, %{"choices" => choices, "usage" => usage}} ->
        messages = parse_choices(choices)
        formatted_usage = %{
          total_tokens: usage["total_tokens"],
          input_tokens: usage["prompt_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || 0
        }
        {:ok, messages, formatted_usage}

      {:ok, _} ->
        {:error, "Baseten Error: Invalid response format"}

      {:error, _} ->
        {:error, "Baseten Error: Failed to parse JSON response"}
    end
  end

  defp parse_rate_limit_response(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        {:rate_limit, "Baseten rate limit: #{message}"}

      {:ok, %{"message" => message}} ->
        {:rate_limit, "Baseten rate limit: #{message}"}

      {:error, _} ->
        # Handle raw string responses like "Rate limit exceeded"
        case String.trim(body) do
          "" -> {:rate_limit, "Baseten rate limit exceeded"}
          msg -> {:rate_limit, "Baseten rate limit: #{msg}"}
        end
    end
  end

  defp parse_error_response(status_code, body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        {:error, "Baseten Error (#{status_code}): #{message}"}

      {:ok, %{"error" => message}} when is_binary(message) ->
        {:error, "Baseten Error (#{status_code}): #{message}"}

      {:ok, %{"message" => message}} ->
        {:error, "Baseten Error (#{status_code}): #{message}"}

      {:error, _} ->
        # Handle raw string responses
        case String.trim(body) do
          "" -> {:error, "Baseten Error (#{status_code}): Unknown error"}
          msg -> {:error, "Baseten Error (#{status_code}): #{msg}"}
        end
    end
  end

  defp parse_choices(choices) do
    choices
    |> Enum.map(fn choice ->
      case choice do
        %{"message" => %{"role" => role, "content" => content, "tool_calls" => tool_calls}}
        when is_list(tool_calls) ->
          formatted_tool_calls =
            Enum.map(tool_calls, fn tool_call ->
              %{
                id: tool_call["id"],
                type: tool_call["type"],
                function: %{
                  name: tool_call["function"]["name"],
                  arguments: tool_call["function"]["arguments"]
                }
              }
            end)

          %Message{role: role, content: content, tool_calls: formatted_tool_calls}

        %{
          "message" => %{
            "role" => role,
            "content" => content,
            "tool_calls" => invalid_tool_calls
          }
        } ->
          # Handle case where tool_calls field exists but contains invalid data
          Logger.warning(
            "Baseten returned invalid tool_calls format: #{inspect(invalid_tool_calls)}"
          )

          %Message{role: role, content: content, tool_calls: nil}

        %{"message" => %{"role" => role, "content" => content}} ->
          # Normal text response without tool_calls
          %Message{role: role, content: content, tool_calls: nil}

        unexpected ->
          Logger.error("Unexpected Baseten message format: #{inspect(unexpected)}")
          %Message{role: "assistant", content: "Error parsing response", tool_calls: nil}
      end
    end)
  end

  defp get_baseten_config do
    case Application.get_env(:dantex, :providers) do
      nil -> []
      providers when is_list(providers) -> Keyword.get(providers, :baseten, [])
      providers when is_map(providers) -> Map.get(providers, :baseten, %{}) |> Map.to_list()
    end
  end
end

