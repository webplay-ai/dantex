defmodule Dantex.Providers.OpenAI do
  @behaviour Dantex.Provider

  require Logger

  @doc """
  Makes a completion request to OpenAI's GPT-4 model.

  ## Parameters
    * `prompt` - The text prompt to send to the model
    * `format` - The format of the response

  ## Returns
    * `{:ok, %{"something": "...", "another_prop": ...}}` - The generated content as a map
    * `{:error, reason}` - If the API request fails
    * `{:rate_limit, reason}` - If the rate limit is exceeded

  ## Examples
      iex> Breaking.Ai.completion("What is 2+2?", %{type: "json_object"})
      {:ok, %{"..."}}
  """

  alias OpenaiEx.Chat
  alias Dantex.Message

  @spec chat_completion(String.t(), list(Message.t())) ::
          {:ok, list(Message.t()), Dantex.Provider.usage()}
          | {:error, String.t()}
          | {:rate_limit, String.t()}
  def chat_completion(model, messages, tools \\ []) do
    api_key = Dantex.Providers.Config.get_api_key(:openai)
    cfg = OpenaiEx.new(api_key) |> OpenaiEx.with_receive_timeout(110_000)

    req =
      if Enum.empty?(tools) do
        Chat.Completions.new(
          model: model,
          messages: format_messages(messages),
          temperature: 0.0
        )
      else
        # formatted_tools = format_tools(tools)

        Chat.Completions.new(
          model: model,
          messages: format_messages(messages),
          temperature: 0.0,
          # tools: formatted_tools
        )
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec format_messages([Message.t()]) :: list(map())
  defp format_messages(messages) do
    Enum.map(messages, fn %{role: role, content: content} ->
      %{role: role, content: content}
    end)
  end

  @spec parse_response(map()) :: {:ok, [Message.t()], Dantex.Provider.usage()} | {:error, term()}
  defp parse_response(%{"choices" => choices, "usage" => usage}) do
    messages =
      choices
      |> Enum.map(fn %{"message" => %{"role" => role, "content" => content}} ->
        %Message{role: role, content: content}
      end)

    # Transform OpenAI usage to match our Provider.usage type
    formatted_usage = %{
      total_tokens: usage["total_tokens"]
    }

    {:ok, messages, formatted_usage}
  end

  defp parse_response(_), do: {:error, "Invalid message format"}

end
