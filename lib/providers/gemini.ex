defmodule Dantex.Providers.Gemini do
  @supported_models [
    "gemini-2.0-flash",
    "gemini-2.0-flash-lite",
    "gemini-1.5-flash",
    "gemini-1.5-flash-8b",
    "gemini-1.5-pro"
  ]

  @moduledoc """
  Provides an interface to the Gemini LLM.
  """
  alias Dantex.Message
  alias Dantex.Provider
  alias Dantex.Tool
  @behaviour Provider

  require Logger

  @doc """
  Generates content using the Gemini LLM.

  ## Parameters

    * `model` - The model name to use (e.g., "gemini-2.0-flash")
    * `messages` - List of messages in the conversation
    * `tools` - List of tools to make available to the model

  ## Returns

  The generated content, or an error message.
  """
  @spec chat_completion(String.t(), [Message.t()], list(Tool.t())) ::
          {:ok, [Message.t()], Provider.usage()} | {:error, String.t()}
  def chat_completion(model, messages, tools \\ []) when is_list(messages) do
    unless model in @supported_models do
      {:error, "Invalid model"}
    end

    api_key = Dantex.Providers.Config.get_api_key(:gemini)

    url =
      "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"

    headers = [{"Content-Type", "application/json"}]
    body = build_request_body(messages, tools)

    try do
      # Add comprehensive timeout settings (all in milliseconds)
      timeout_options = [
        timeout: 30_000,         # Overall request timeout (default: 5000)
        recv_timeout: 60_000,    # Response receiving timeout (default: 5000)
        connect_timeout: 10_000  # Connection establishment timeout (default: 8000)
      ]

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

  @spec build_request_body([Message.t()], list(Tool.t())) :: String.t()
  defp build_request_body(messages, tools) do
    contents =
      Enum.map(messages, fn %Message{role: role, content: content} ->
        %{
          role: build_role(role),
          parts: [%{text: content}]
        }
      end)

    request = %{contents: contents}

    # Add tools to the request if provided
    request =
      if Enum.empty?(tools) do
        request
      else
        Map.put(request, :tools, %{
          function_declarations: format_tools(tools)
        })
      end

    Jason.encode!(request)
  end

  @spec format_tools([Tool.t()]) :: list(map())
  defp format_tools(tools) do
    Enum.map(tools, fn tool ->
      # Convert Dantex.Tool to Gemini function declaration format
      %{
        name: tool.tool_name(),
        description: tool.tool_description(),
        parameters: Jason.decode!(tool.generate_tool_json_schema())
      }
    end)
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
        content = Map.get(candidate, "content", %{})
        parts = Map.get(content, "parts", [])

        # Check if there are function calls in the response
        function_calls =
          parts
          |> Enum.filter(fn part -> Map.has_key?(part, "functionCall") end)
          |> Enum.map(fn part ->
            function_call = Map.get(part, "functionCall", %{})

            %{
              # Gemini might not provide IDs, so we generate one
              id: UUID.uuid4(),
              type: "function",
              function: %{
                name: Map.get(function_call, "name", ""),
                arguments: Jason.encode!(Map.get(function_call, "args", %{}))
              }
            }
          end)

        # Get text content if available
        text =
          parts
          |> Enum.filter(fn part -> Map.has_key?(part, "text") end)
          |> Enum.map_join("", fn part -> Map.get(part, "text", "") end)

        if Enum.empty?(function_calls) do
          # Regular message without function calls
          %Message{
            role: "assistant",
            content: text
          }
        else
          # Message with function calls
          %Message{
            role: "assistant",
            content: text,
            tool_calls: function_calls
          }
        end
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
        content = Map.get(candidate, "content", %{})
        parts = Map.get(content, "parts", [])

        # Check if there are function calls in the response
        function_calls =
          parts
          |> Enum.filter(fn part -> Map.has_key?(part, "functionCall") end)
          |> Enum.map(fn part ->
            function_call = Map.get(part, "functionCall", %{})

            %{
              # Gemini might not provide IDs, so we generate one
              id: UUID.uuid4(),
              type: "function",
              function: %{
                name: Map.get(function_call, "name", ""),
                arguments: Jason.encode!(Map.get(function_call, "args", %{}))
              }
            }
          end)

        # Get text content if available
        text =
          parts
          |> Enum.filter(fn part -> Map.has_key?(part, "text") end)
          |> Enum.map_join("", fn part -> Map.get(part, "text", "") end)

        if Enum.empty?(function_calls) do
          # Regular message without function calls
          %Message{
            role: "assistant",
            content: text
          }
        else
          # Message with function calls
          %Message{
            role: "assistant",
            content: text,
            tool_calls: function_calls
          }
        end
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
