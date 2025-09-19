defmodule Dantex.Providers.OpenAI do
  @moduledoc """
  OpenAI provider implementation for chat completions.

  Handles authentication, tool calling, message formatting, and response parsing.
  """

  @behaviour Dantex.Provider

  require Logger

  alias OpenaiEx.Chat
  alias Dantex.Message

  @spec chat_completion(map()) ::
          {:ok, list(Message.t()), Dantex.Provider.usage()}
          | {:error, String.t()}
          | {:rate_limit, String.t()}
  def chat_completion(opts) when is_map(opts) do
    model = Map.get(opts, :model)
    messages = Map.get(opts, :messages, [])
    tools = Map.get(opts, :tools, [])
    timeout = Map.get(opts, :timeout, 180_000)

    api_key = Map.get(opts, :api_key) || Dantex.Providers.Config.get_api_key(:openai)

    base_url =
      Map.get(opts, :base_url) || Dantex.Providers.Config.get_config_value(:openai, :base_url)

    cfg =
      case base_url do
        nil ->
          OpenaiEx.new(api_key) |> OpenaiEx.with_receive_timeout(timeout)

        custom_url ->
          OpenaiEx.new(api_key)
          |> OpenaiEx.with_base_url(custom_url)
          |> OpenaiEx.with_receive_timeout(timeout)
      end

    base_params = [
      model: model,
      messages: format_messages(messages),
      temperature: Map.get(opts, :temperature, 0.0)
    ]

    optional_params = []

    optional_params =
      if Map.has_key?(opts, :max_tokens),
        do: [{:max_tokens, Map.get(opts, :max_tokens)} | optional_params],
        else: optional_params

    optional_params =
      if Map.has_key?(opts, :top_p),
        do: [{:top_p, Map.get(opts, :top_p)} | optional_params],
        else: optional_params

    optional_params =
      if Map.has_key?(opts, :presence_penalty),
        do: [{:presence_penalty, Map.get(opts, :presence_penalty)} | optional_params],
        else: optional_params

    optional_params =
      if Map.has_key?(opts, :frequency_penalty),
        do: [{:frequency_penalty, Map.get(opts, :frequency_penalty)} | optional_params],
        else: optional_params

    optional_params =
      if Map.has_key?(opts, :stop),
        do: [{:stop, Map.get(opts, :stop)} | optional_params],
        else: optional_params

    params = base_params ++ optional_params

    req =
      if Enum.empty?(tools) do
        Chat.Completions.new(params)
      else
        formatted_tools = format_tools(tools)
        Chat.Completions.new([{:tools, formatted_tools} | params])
      end

    with {:ok, result} <-
           Chat.Completions.create(cfg, req),
         {:ok, messages, usage} <- parse_response(result) do
      {:ok, messages, usage}
    else
      {:error, %{reason: :rate_limit_exceeded}} ->
        {:rate_limit, "Rate limit exceeded"}

      {:error, %OpenaiEx.Error{} = error} ->
        {:error, "OpenAI Error: #{error.message || "Unknown error"}"}

      {:error, "Rate limit exceeded"} ->
        {:rate_limit, "Rate limit exceeded"}

      {:error, reason} when is_binary(reason) ->
        case String.contains?(String.downcase(reason), "rate limit") do
          true -> {:rate_limit, reason}
          false -> {:error, reason}
        end

      {:error, reason} ->
        {:error, inspect(reason)}
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

  @spec parse_response(map()) :: {:ok, [Message.t()], Dantex.Provider.usage()} | {:error, term()}
  defp parse_response(%{"choices" => choices, "usage" => usage}) do
    messages =
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
            require Logger

            Logger.warning(
              "OpenAI returned invalid tool_calls format: #{inspect(invalid_tool_calls)}"
            )

            %Message{role: role, content: content, tool_calls: nil}

          %{"message" => %{"role" => role, "content" => content}} ->
            # Normal text response without tool_calls
            %Message{role: role, content: content, tool_calls: nil}

          unexpected ->
            require Logger
            Logger.error("Unexpected OpenAI message format: #{inspect(unexpected)}")
            %Message{role: "assistant", content: "Error parsing response", tool_calls: nil}
        end
      end)

    formatted_usage = %{
      total_tokens: usage["total_tokens"]
    }

    {:ok, messages, formatted_usage}
  end

  defp parse_response(_), do: {:error, "Invalid message format"}
end
