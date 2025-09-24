defmodule Dantex.Providers.Ollama do
  @supported_models [
    "gemma3:4b",
    "gemma3:1b",
    "gemma3:7b",
    "gemma3:12b",

    "deepseek-r1:1.5b",
    "deepseek-r1:7b",
    "deepseek-r1:8b",
    "deepseek-r1:14b",
    "deepseek-r1:32b",

    "llama3.2",
    "llama3.2:1b"
  ]

  @moduledoc """
  Provides an interface to the Ollama LLM service.
  """
  alias Dantex.Message
  alias Dantex.Provider
  alias Dantex.Tool
  @behaviour Provider

  require Logger

  @default_api_base "http://localhost:11434"

  @doc """
  Generates content using the Ollama LLM service.

  ## Parameters

    * `model` - The model name to use (e.g., "llama2", "mistral", etc.)
    * `messages` - List of messages in the conversation
    * `tools` - List of tools to make available to the model

  ## Returns

  The generated content, or an error message.
  """
  @spec chat_completion(map()) ::
          {:ok, [Message.t()], Provider.usage()} | {:error, String.t()}
  def chat_completion(opts) when is_map(opts) do
    # Extract required parameters
    model = Map.get(opts, :model)
    messages = Map.get(opts, :messages, [])
    tools = Map.get(opts, :tools, [])
    timeout = Map.get(opts, :timeout)
    temperature = Map.get(opts, :temperature)
    
    unless model in @supported_models do
      {:error, "Invalid model"}
    end

    api_base = Map.get(opts, :api_base) || Dantex.Providers.Config.get_config_value(:ollama, :api_base) || @default_api_base
    url = "#{api_base}/api/chat"

    headers = [{"Content-Type", "application/json"}]
    body = build_request_body(model, messages, tools, temperature)

    try do
      # Add comprehensive timeout settings (all in milliseconds)
      timeout_options = case timeout do
        nil -> [
          timeout: 30_000,         # Overall request timeout (default: 5000)
          recv_timeout: 60_000,    # Response receiving timeout (default: 5000)
          connect_timeout: 10_000  # Connection establishment timeout (default: 8000)
        ]
        custom_timeout -> [
          timeout: custom_timeout,
          recv_timeout: custom_timeout + 30_000,
          connect_timeout: 10_000
        ]
      end

      {:ok, %{status_code: status_code, body: body}} =
        HTTPoison.post(url, body, headers, timeout_options)

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

  @spec build_request_body(String.t(), [Message.t()], list(Tool.t()), float() | nil) :: String.t()
  defp build_request_body(model, messages, tools, temperature) do
    formatted_messages =
      Enum.map(messages, fn message ->
        case message do
          %Message{role: role, content: content, tool_calls: _tool_calls} ->
            %{
              role: role,
              content: content
            }

          %Message{role: role, content: content, tool_call_id: tool_call_id}
          when not is_nil(tool_call_id) ->
            %{
              role: role,
              content: content,
              tool_call_id: tool_call_id
            }

          %Message{role: role, content: content} ->
            %{
              role: role,
              content: content
            }
        end
      end)

    request = %{
      model: model,
      messages: formatted_messages,
      stream: false
    }

    # Add tools to the request if provided
    request =
      if Enum.empty?(tools) do
        request
      else
        Map.put(request, :tools, format_tools(tools))
      end

    # Add options with temperature if provided
    request =
      if temperature == nil do
        request
      else
        Map.put(request, :options, %{
          temperature: temperature
        })
      end

    Jason.encode!(request)
  end

  @spec format_tools([Tool.t()]) :: list(map())
  defp format_tools(tools) do
    Enum.map(tools, fn tool ->
      # Convert Dantex.Tool to Ollama tool format
      # Note: Ollama's tool format may differ from OpenAI's
      %{
        type: "function",
        function: %{
          name: tool.tool_name(),
          description: tool.tool_description(),
          parameters: Jason.decode!(tool.generate_tool_json_schema())
        }
      }
    end)
  end

  @spec parse_response(map()) ::
          {:ok, [Message.t()], Provider.usage()} | {:error, String.t()}
  defp parse_response(%{
         "message" => %{"role" => role, "content" => content, "tool_calls" => tool_calls},
         "eval_count" => eval_count
       }) do
    # Convert tool_calls to our structured type
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

    message = %Message{
      role: role,
      content: content,
      tool_calls: formatted_tool_calls
    }

    formatted_usage = %{
      total_tokens: eval_count,
      input_tokens: 0,
      output_tokens: eval_count
    }

    {:ok, [message], formatted_usage}
  end

  defp parse_response(%{
         "message" => %{"role" => role, "content" => content},
         "eval_count" => eval_count
       }) do
    message = %Message{
      role: role,
      content: content
    }

    # Ollama provides eval_count which is roughly equivalent to the number of tokens generated
    # For total tokens, we make a rough estimate based on the input and output
    formatted_usage = %{
      total_tokens: eval_count,
      input_tokens: 0,
      output_tokens: eval_count
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
      total_tokens: 0,
      input_tokens: 0,
      output_tokens: 0
    }

    {:ok, [message], formatted_usage}
  end

  defp parse_response(_), do: {:error, "Invalid response format"}
end
