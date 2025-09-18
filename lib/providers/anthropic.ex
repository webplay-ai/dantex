defmodule Dantex.Providers.Anthropic do
  @moduledoc """
  Anthropic provider implementation for chat completions.
  
  Supports various Claude models including Claude 3.5 Sonnet, Claude 3 Opus, and Claude 3 Haiku.
  Handles authentication, tool calling, message formatting, and response parsing.
  """
  @supported_models [
    "claude-3-5-sonnet-20241022",
    "claude-3-5-sonnet-20240620", 
    "claude-3-5-haiku-20241022",
    "claude-3-opus-20240229",
    "claude-3-sonnet-20240229",
    "claude-3-haiku-20240307"
  ]

  @behaviour Dantex.Provider

  require Logger

  alias Dantex.Message

  @spec chat_completion(map()) ::
          {:ok, list(Message.t()), Dantex.Provider.usage()}
          | {:error, String.t()}
          | {:rate_limit, String.t()}
  def chat_completion(opts) when is_map(opts) do
    # Extract required parameters
    model = Map.get(opts, :model)
    messages = Map.get(opts, :messages, [])
    tools = Map.get(opts, :tools, [])
    
    unless model in @supported_models do
      {:error, "Invalid model"}
    end

    api_key = Dantex.Providers.Config.get_api_key(:anthropic)
    
    unless api_key do
      {:error, "Anthropic API key not configured"}
    end

    url = "https://api.anthropic.com/v1/messages"
    
    headers = [
      {"Content-Type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]

    body = build_request_body(model, messages, tools)

    try do
      timeout_options = [
        timeout: 60_000,         # Overall request timeout
        recv_timeout: 120_000,   # Response receiving timeout
        connect_timeout: 10_000  # Connection establishment timeout
      ]

      {:ok, %{status_code: status_code, body: response_body}} =
        HTTPoison.post(url, body, headers, timeout_options)

      case status_code do
        200 ->
          case Jason.decode(response_body) do
            {:ok, response} ->
              parse_response(response)

            {:error, error} ->
              Logger.error("Failed to decode JSON: #{inspect(error)}")
              {:error, "Failed to decode JSON: #{error}"}
          end

        429 ->
          Logger.error("Anthropic API rate limit exceeded")
          {:rate_limit, "Rate limit exceeded"}

        _ ->
          Logger.error(
            "Anthropic API request failed with status code: #{status_code} and body: #{response_body}"
          )

          {:error, "Anthropic API request failed with status code: #{status_code}"}
      end
    rescue
      e ->
        Logger.error("Anthropic API request failed with exception: #{inspect(e)}")
        {:error, "Anthropic API request failed with exception: #{inspect(e)}"}
    end
  end

  @spec build_request_body(String.t(), [Message.t()], list(Dantex.Tool.t())) :: String.t()
  defp build_request_body(model, messages, tools) do
    # Separate system messages from user/assistant messages
    {system_messages, conversation_messages} = split_system_messages(messages)
    
    # Build the base request
    request = %{
      model: model,
      max_tokens: 4096,
      messages: format_messages(conversation_messages)
    }

    # Add system prompt if present
    request = 
      case extract_system_content(system_messages) do
        "" -> request
        system_content -> Map.put(request, :system, system_content)
      end

    # Add tools if provided
    request =
      if Enum.empty?(tools) do
        request
      else
        Map.put(request, :tools, format_tools(tools))
      end

    Jason.encode!(request)
  end

  @spec split_system_messages([Message.t()]) :: {[Message.t()], [Message.t()]}
  defp split_system_messages(messages) do
    Enum.split_with(messages, fn %Message{role: role} -> role == "system" end)
  end

  @spec extract_system_content([Message.t()]) :: String.t()
  defp extract_system_content(system_messages) do
    system_messages
    |> Enum.map_join("\n\n", fn %Message{content: content} -> content end)
  end

  @spec format_messages([Message.t()]) :: list(map())
  defp format_messages(messages) do
    Enum.map(messages, fn message ->
      case message do
        %{role: role, content: content, tool_calls: tool_calls} when not is_nil(tool_calls) ->
          # Format tool calls for Anthropic
          formatted_content = [%{type: "text", text: content || ""}]
          
          tool_content = Enum.map(tool_calls, fn tool_call ->
            %{
              type: "tool_use",
              id: tool_call.id,
              name: tool_call.function.name,
              input: Jason.decode!(tool_call.function.arguments)
            }
          end)

          %{role: role, content: formatted_content ++ tool_content}

        %{role: role, content: content, tool_call_id: tool_call_id} when not is_nil(tool_call_id) ->
          # Tool result message
          %{
            role: role,
            content: [
              %{
                type: "tool_result",
                tool_use_id: tool_call_id,
                content: content
              }
            ]
          }

        %{role: role, content: content} ->
          %{role: role, content: [%{type: "text", text: content}]}
      end
    end)
  end

  @spec format_tools([Dantex.Tool.t()]) :: list(map())
  defp format_tools(tools) do
    Enum.map(tools, fn tool ->
      schema = Jason.decode!(tool.generate_tool_json_schema())
      
      %{
        name: schema["function"]["name"],
        description: schema["function"]["description"],
        input_schema: schema["function"]["parameters"]
      }
    end)
  end

  @spec parse_response(map()) :: {:ok, [Message.t()], Dantex.Provider.usage()} | {:error, term()}
  defp parse_response(%{"content" => content, "usage" => usage}) do
    messages = parse_content_blocks(content)
    
    formatted_usage = %{
      total_tokens: usage["input_tokens"] + usage["output_tokens"]
    }

    {:ok, messages, formatted_usage}
  end

  defp parse_response(_), do: {:error, "Invalid response format"}

  @spec parse_content_blocks(list(map())) :: [Message.t()]
  defp parse_content_blocks(content_blocks) do
    # Group content blocks by type
    text_content = extract_text_content(content_blocks)
    tool_calls = extract_tool_calls(content_blocks)

    message = %Message{
      role: "assistant",
      content: text_content
    }

    # Add tool calls if present
    if Enum.empty?(tool_calls) do
      [message]
    else
      [%{message | tool_calls: tool_calls}]
    end
  end

  @spec extract_text_content(list(map())) :: String.t()
  defp extract_text_content(content_blocks) do
    content_blocks
    |> Enum.filter(fn block -> block["type"] == "text" end)
    |> Enum.map_join("", fn block -> block["text"] || "" end)
  end

  @spec extract_tool_calls(list(map())) :: list(map())
  defp extract_tool_calls(content_blocks) do
    content_blocks
    |> Enum.filter(fn block -> block["type"] == "tool_use" end)
    |> Enum.map(fn block ->
      %{
        id: block["id"],
        type: "function",
        function: %{
          name: block["name"],
          arguments: Jason.encode!(block["input"])
        }
      }
    end)
  end
end