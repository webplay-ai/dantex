defmodule Dantex.Providers.Together do
  @moduledoc """
  Together AI provider implementation for chat completions.

  Direct HTTP implementation for Together AI's OpenAI-compatible API endpoints
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
    together_config = get_together_config()

    unless together_config[:api_key] do
      {:error, "Together AI API key not configured"}
    end

    model = Map.get(opts, :model)
    messages = Map.get(opts, :messages, [])
    tools = Map.get(opts, :tools, [])
    timeout = Map.get(opts, :timeout, 180_000)

    api_key = together_config[:api_key]
    base_url = together_config[:base_url] || "https://api.together.xyz"

    # Build request payload
    payload = %{
      model: model,
      messages: format_messages(messages),
      temperature: Map.get(opts, :temperature, together_config[:temperature] || 0.7),
      max_tokens: Map.get(opts, :max_tokens, together_config[:max_tokens] || 512),
      top_p: Map.get(opts, :top_p, together_config[:top_p] || 0.7),
      stop: Map.get(opts, :stop, together_config[:stop] || [])
    }

    # Add tools if provided
    payload =
      if Enum.empty?(tools) do
        payload
      else
        Map.put(payload, :tools, format_tools(tools))
      end

    # Add Together-specific parameters if configured
    payload =
      payload
      |> maybe_add_safety_model(together_config)
      |> maybe_add_stream(opts, together_config)

    # Make HTTP request
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    url = "#{base_url}/v1/chat/completions"

    # Add comprehensive timeout settings (all in milliseconds)
    timeout_options = case timeout do
      nil -> [
        timeout: 60_000,         # Overall request timeout
        recv_timeout: 180_000,   # Response receiving timeout
        connect_timeout: 15_000  # Connection establishment timeout
      ]
      custom_timeout -> [
        timeout: custom_timeout,
        recv_timeout: custom_timeout * 2,
        connect_timeout: 15_000
      ]
    end

    case HTTPoison.post(url, Jason.encode!(payload), headers, timeout_options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_success_response(body)

      {:ok, %HTTPoison.Response{status_code: 429, body: body}} ->
        parse_rate_limit_response(body)

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        parse_error_response(status_code, body)

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Together AI HTTP Error: #{inspect(reason)}"}
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

  defp maybe_add_safety_model(payload, config) do
    case config[:safety_model] do
      nil -> payload
      safety_model -> Map.put(payload, :safety_model, safety_model)
    end
  end

  defp maybe_add_stream(payload, opts, config) do
    stream = Map.get(opts, :stream, config[:stream] || false)
    Map.put(payload, :stream, stream)
  end

  defp parse_success_response(body) do
    case Jason.decode(body) do
      {:ok, %{"choices" => choices, "usage" => usage}} ->
        messages = parse_choices(choices)
        formatted_usage = %{total_tokens: usage["total_tokens"]}
        {:ok, messages, formatted_usage}

      {:ok, _} ->
        {:error, "Together AI Error: Invalid response format"}

      {:error, _} ->
        {:error, "Together AI Error: Failed to parse JSON response"}
    end
  end

  defp parse_rate_limit_response(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        {:rate_limit, "Together AI rate limit: #{message}"}

      {:ok, %{"message" => message}} ->
        {:rate_limit, "Together AI rate limit: #{message}"}

      {:error, _} ->
        # Handle raw string responses
        case String.trim(body) do
          "" -> {:rate_limit, "Together AI rate limit exceeded"}
          msg -> {:rate_limit, "Together AI rate limit: #{msg}"}
        end
    end
  end

  defp parse_error_response(status_code, body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        {:error, "Together AI Error (#{status_code}): #{message}"}

      {:ok, %{"message" => message}} ->
        {:error, "Together AI Error (#{status_code}): #{message}"}

      {:error, _} ->
        # Handle raw string responses
        case String.trim(body) do
          "" -> {:error, "Together AI Error (#{status_code}): Unknown error"}
          msg -> {:error, "Together AI Error (#{status_code}): #{msg}"}
        end
    end
  end

  # Make public for testing
  def parse_choices(choices) do
    choices
    |> Enum.map(fn choice ->
      case choice do
        %{"message" => %{"role" => role, "content" => content, "tool_calls" => tool_calls}}
        when is_list(tool_calls) ->
          formatted_tool_calls =
            Enum.map(tool_calls, fn tool_call ->
              # Handle potential missing fields gracefully
              function_data = tool_call["function"] || %{}

              %{
                id: tool_call["id"] || generate_tool_call_id(),
                type: tool_call["type"] || "function",
                function: %{
                  name: function_data["name"] || "unknown_function",
                  arguments: function_data["arguments"] || "{}"
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
            "Together AI returned invalid tool_calls format: #{inspect(invalid_tool_calls)}"
          )

          %Message{role: role, content: content, tool_calls: nil}

        %{"message" => %{"role" => role, "content" => content, "function_call" => function_call}}
        when not is_nil(function_call) ->
          # Handle legacy function_call format (single function call)
          formatted_tool_calls = [
            %{
              id: generate_tool_call_id(),
              type: "function",
              function: %{
                name: function_call["name"] || "unknown_function",
                arguments: function_call["arguments"] || "{}"
              }
            }
          ]

          %Message{role: role, content: content, tool_calls: formatted_tool_calls}

        %{"message" => %{"role" => role, "content" => content}} ->
          # Normal text response without tool_calls
          %Message{role: role, content: content, tool_calls: nil}

        unexpected ->
          Logger.error("Unexpected Together AI message format: #{inspect(unexpected)}")
          %Message{role: "assistant", content: "Error parsing response", tool_calls: nil}
      end
    end)
  end

  defp get_together_config do
    case Application.get_env(:dantex, :providers) do
      nil -> []
      providers when is_list(providers) -> Keyword.get(providers, :together, [])
      providers when is_map(providers) -> Map.get(providers, :together, %{}) |> Map.to_list()
    end
  end

  # Generate a unique tool call ID for legacy function_call format
  defp generate_tool_call_id do
    "call_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
