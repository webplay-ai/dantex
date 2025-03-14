defmodule Dantex.Agent do
  @moduledoc """
  Agents are containers that group model, system prompt, tooling, response formats,
  tool call history, and retry limits.

  Agents can track the history of tool calls and enforce limits on the number of failed
  retries for a given tool and set of arguments.

  Future considerations:
  - How about if agents could decide to use different LLMs and switch from model in function tool calling theirselves? We just have to move the model to the run function instead. That would mean an agent is nothing more then a bunch of messages. You can have replace the system prompt.

  ## Example

      alias Dante.{Agent, Model, Prompt, Response, ResponseFormat, Message}

      model = Model.new("gpt-4")

      # or a mock model so we can unit or end 2 end test our business logic
      mock = Model.mock([%{ role: system, content: "foo"}])
      mock.pushMessages([%{ role: user, content: "another message"}])

      # Define a plain tool
      defmodule DiceTool do
        use Dantex.Tool.Plain

        @tool_name "roll_die"
        @tool_description "Roll a six-sided die and return the result"

        def call(_params) do
          {:ok, Integer.to_string(Enum.random(1..6))}
        end
      end

      # Create an agent
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini,
        messages: [],
        tools: [DiceTool], // optional
        max_failed_retries: 3 // optional
      )

      # Run the agent
      {:ok, {last_msg, _, _, _}, _} = Agent.run(agent, "Roll the die")
  """

  alias Dantex.{Tool, Model, Tool, Message, Provider}

  @type t :: %__MODULE__{
          model: Model.t(),
          tools: [Tool.t()],
          messages: [Message.t()],
          tool_history: [Tool.ToolHistory.t()],
          max_failed_retries: non_neg_integer() | nil
          # logger: module() | nil
        }

  defstruct [
    :model,
    :tools,
    :messages,
    :tool_history,
    :max_failed_retries
    # :logger
  ]

  @doc """
  Creates a new agent with the given configuration.

  ## Options

    * `:provider` - The AI model provider to use (required)
    * `:model` - The AI model to use (required)
    * `:messages` - A list of prompt messages (required)
    * `:tools` - List of tool modules to use (default: [])
    * `:max_failed_retries` - The maximum number of failed retries for a tool call with the same arguments (optional, default: nil)

  ## Example

      Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [Message{content: "You are a helpful assistant", role: "system"}],
        tools: [WeatherTool, TimeTool],
        max_failed_retries: 3
      )
  """
  require Logger

  @spec new([
          {:provider, atom()}
          | {:model, String.t()}
          | {:messages, [Message.t()]}
          | {:tools, [Tool.t()]}
          | {:max_failed_retries, non_neg_integer()}
        ]) ::
          t()
  def new(opts) do
    provider = Keyword.get(opts, :provider, :openai)
    model = Keyword.get(opts, :model, "gpt-4o-mini")
    tools = Keyword.get(opts, :tools, [])
    messages = Keyword.get(opts, :messages, [])

    %__MODULE__{
      model: Model.new(provider, model),
      messages: messages,
      tools: tools,
      tool_history: [],
      max_failed_retries: Keyword.get(opts, :max_failed_retries, nil)
      # logger: logger
    }
  end

  @doc """
  Adds additional tools to an existing agent.

  ## Example

      agent = Agent.new(model: "gpt-4", system_prompt: "...")
      agent = Agent.add_tools(agent, [WeatherTool, TimeTool])
  """
  @spec add_tools(t(), [Tool.t()]) :: t()
  def add_tools(%__MODULE__{} = agent, tools) when is_list(tools) do
    %{agent | tools: agent.tools ++ tools}
  end

  @type tool_result :: %{
    tool_name: String.t(),
    input_parameters: map(),
    output: map()
  }

  @doc """
  Runs the agent with the given prompt.

  ## Example

      {:ok, response} = Agent.run(agent, "What's the weather?")
  """
  @spec run(t(), Message.t() | String.t()) ::
          {:ok, {Message.t(), [Message.t()], t(), list(tool_result()) | nil}, Provider.usage()} | {:error, term()}
  def run(%__MODULE__{} = agent, user_prompt) do
    with {:ok, messages} <- build_messages(agent, user_prompt),
         {:ok, {last_msg, all_msgs}, usage} <- chat_completion(agent, messages) do
      # Check if the last message contains tool calls
      case last_msg do
        %Message{tool_calls: tool_calls} when is_list(tool_calls) and length(tool_calls) > 0 ->
          {tool_results, updated_messages} = execute_tool_calls(agent, tool_calls, all_msgs)
          updated_agent = update_tool_history(agent, tool_results)
          run_with_tool_results(updated_agent, updated_messages, tool_results, usage)

        _ ->
          updated_agent = %{agent | messages: messages ++ [last_msg]}
          {:ok, {last_msg, all_msgs, updated_agent, nil}, usage}
      end
    end
  end

  @spec execute_tool_calls(t(), list(Message.tool_call()), list(Message.t())) ::
          {list({Message.tool_call(), Message.t(), map()}), list(Message.t())}
  defp execute_tool_calls(agent, tool_calls, messages) do
    tool_results =
      tool_calls
      |> Enum.map(fn tool_call ->
        tool_name = tool_call.function.name
        tool = Enum.find(agent.tools, fn t -> t.tool_name() == tool_name end)

        arguments = Jason.decode!(tool_call.function.arguments)

        # Check if max_failed_retries is exceeded
        if agent.max_failed_retries && exceeded_failed_retries?(agent, tool_name, arguments) do
          # Return an error message
          tool_result = Message.tool_result(tool_call.id, %{error: "Max failed retries exceeded"})
          {tool_call, tool_result, %{error: "Max failed retries exceeded"}}
        else
          # Execute the tool
          case tool.call(arguments) do
            {:ok, result} ->
              # Create a tool result message
              tool_result = Message.tool_result(tool_call.id, result)
              {tool_call, tool_result, result}

            {:error, error} ->
              # Create an error message
              tool_result = Message.tool_result(tool_call.id, %{error: error})
              {tool_call, tool_result, %{error: error}}
          end
        end
      end)

    # Add tool results to messages
    updated_messages =
      messages ++
      Enum.map(tool_results, fn {_, tool_result, _} -> tool_result end)

    {tool_results, updated_messages}
  end

  @doc """
  Runs the agent with the given prompt and tool results.
  """
  @spec run_with_tool_results(t(), list(Message.t()), list({Message.tool_call(), Message.t(), map()}), Provider.usage()) ::
          {:ok, {Message.t(), [Message.t()], t(), list(tool_result())}, Provider.usage()} | {:error, term()}
  defp run_with_tool_results(agent, messages, tool_results, usage) do
    with {:ok, {last_msg, all_msgs}, new_usage} <- chat_completion(agent, messages) do
      combined_usage = %{
        total_tokens: usage.total_tokens + new_usage.total_tokens
      }

      updated_agent = %{agent | messages: messages ++ [last_msg]}

      formatted_results =
        tool_results
        |> Enum.map(fn {tool_call, _, result} ->
          %{
            tool_name: tool_call.function.name,
            input_parameters: Jason.decode!(tool_call.function.arguments),
            output: result
          }
        end)

      # Return the result
      {:ok, {last_msg, all_msgs, updated_agent, formatted_results}, combined_usage}
    end
  end

  @spec build_messages(t(), Message.t() | String.t()) :: {:ok, list(Message.t())}
  defp build_messages(%__MODULE__{messages: messages} = agent, %Message{} = user_prompt) do
    {:ok, messages ++ [user_prompt]}
  end

  defp build_messages(%__MODULE__{messages: messages} = agent, user_prompt)
       when is_binary(user_prompt) do
    {:ok, messages ++ [Message.user(user_prompt)]}
  end

  @spec chat_completion(t(), list(Message.t())) ::
          {:ok, {Message.t(), [Message.t()]}, Provider.usage()} | {:error, term()}
  defp(chat_completion(agent, messages)) do
    Model.chat_completion(agent.model, messages, agent.tools)
  end

  defp exceeded_failed_retries?(agent, tool_name, arguments) do
    agent.tool_history
    |> Enum.filter(fn entry ->
      entry.tool_name == tool_name && entry.input_parameters == arguments && is_map_key(entry.output, :error)
    end)
    |> length() >= agent.max_failed_retries
  end

  defp update_tool_history(%__MODULE__{tool_history: history} = agent, tool_results) do
    updated_history =
      Enum.reduce(tool_results, history, fn {tool_call, _tool_result, result}, acc ->
        tool_history_entry = %Dantex.Tool.ToolHistory{
          tool_name: tool_call.function.name,
          input_parameters: Jason.decode!(tool_call.function.arguments),
          output: result,
          timestamp: DateTime.utc_now()
        }
        [tool_history_entry | acc]
      end)

    %{agent | tool_history: updated_history}
  end
end
