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
        messages: mock,
        tools: [DiceTool], // optional
        max_failed_retries: 3 // optional
      )

      # Run the agent
      {:ok, {last_msg, _, _, _}, _} = Agent.run(agent, "Roll the die")
  """

  alias Dantex.{Tool, Model, Message, Provider}
  alias Dantex.Tool.{OpenAIAdapter, ToolAdapter}

  @type t :: %__MODULE__{
          model: Model.t(),
          tools: [Tool.t()],
          messages: [Message.t()],
          tool_history: [Tool.ToolHistory.t()],
          max_failed_retries: non_neg_integer() | nil,
          tool_adapter: module()
        }

  defstruct [
    :model,
    :tools,
    :messages,
    :tool_history,
    :max_failed_retries,
    :tool_adapter
  ]

  @doc """
  Creates a new agent with the given configuration.

  ## Options

    * `:provider` - The AI model provider to use (required)
    * `:model` - The AI model to use (required)
    * `:messages` - A list of prompt messages (required)
    * `:tools` - List of tool modules to use (default: [])
    * `:max_failed_retries` - The maximum number of failed retries for a tool call with the same arguments (optional, default: nil)
    * `:tool_adapter` - The tool adapter module to use (default: OpenAIAdapter for OpenAI provider, XMLAdapter for other providers)

  ## Example

      Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [Message{content: "You are a helpful assistant", role: "system"}],
        tools: [WeatherTool, TimeTool],
        max_failed_retries: 3,
        tool_adapter: OpenAIAdapter
      )
  """
  require Logger

  @spec new([
          {:provider, atom()}
          | {:model, String.t()}
          | {:messages, [Message.t()]}
          | {:tools, [Tool.t()]}
          | {:max_failed_retries, non_neg_integer()}
          | {:tool_adapter, ToolAdapter.t()}
        ]) ::
          t()
  def new(opts) do
    provider = Keyword.get(opts, :provider, :openai)
    model = Keyword.get(opts, :model, "gpt-4o-mini")
    tools = Keyword.get(opts, :tools, [])
    messages = Keyword.get(opts, :messages, [])
    max_failed_retries = Keyword.get(opts, :max_failed_retries, 0) # 0, equals disabled
    tool_adapter = Keyword.get(opts, :tool_adapter, OpenAIAdapter)

    %__MODULE__{
      model: Model.new(provider, model),
      messages: messages,
      tools: tools,
      tool_history: [],
      max_failed_retries: max_failed_retries,
      tool_adapter: tool_adapter
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

  @doc """
  Sets the tool adapter for the agent.

  ## Example

      agent = Agent.new(provider: :openai, model: "gpt-4")
      agent = Agent.set_tool_adapter(agent, Dantex.Tool.XMLAdapter)
  """
  @spec set_tool_adapter(t(), module()) :: t()
  def set_tool_adapter(%__MODULE__{} = agent, adapter) do
    %{agent | tool_adapter: adapter}
  end

  @doc """
  Sets the maximum number of failed retries for a tool call with the same arguments.

  ## Example

      agent = Agent.new(provider: :openai, model: "gpt-4")
      agent = Agent.set_max_failed_retries(agent, 3)
  """
  @spec set_max_failed_retries(t(), non_neg_integer() | nil) :: t()
  def set_max_failed_retries(%__MODULE__{} = agent, max_failed_retries) do
    %{agent | max_failed_retries: max_failed_retries}
  end

  @type tool_result :: %{
    tool_name: String.t(),
    input_parameters: map(),
    output: map()
  }

  @doc """
  Runs the agent with the given prompt. This is what happens:

  1. It adds the message to the agent.messages
  2. Runs the chat completions
  3. It tries to extract a tool call from the response - a no-op for OpenAI and Ollama
  4. In case there is a tool call:
     a. Check if we exceed the max_failed_retries limit. If not execute using the tool adapter, otherwise return with an Dantex.Message containing an error
     b. Add the tool call results to the agent.messages
     c. Update the tool history
  5. Return with updated agent state, history and messages
  """
  @spec run(t(), Message.t() | String.t()) ::
          {:ok, {Message.t(), [Message.t()], t(), list(tool_result()) | nil}, Provider.usage()} | {:error, term()}
  def run(%__MODULE__{} = agent, message) do
    with {:ok, messages} <- build_messages(agent, message),
         {:ok, {last_msg, all_msgs}, usage} <- chat_completion(agent, messages),
         {:ok, processed_msg} <- agent.tool_adapter.extract_function_calls(last_msg) do
      process_message(agent, processed_msg, messages, all_msgs, usage)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Processes the message based on whether it contains tool calls or not.
  """
  @spec process_message(t(), Message.t(), [Message.t()], [Message.t()], Provider.usage()) ::
          {:ok, {Message.t(), [Message.t()], t(), list(tool_result()) | nil}, Provider.usage()}
  defp process_message(agent, %{tool_calls: tool_calls} = last_msg, messages, all_msgs, usage)
       when is_list(tool_calls) and length(tool_calls) > 0 do
    process_tool_calls(agent, last_msg, all_msgs, usage)
  end

  defp process_message(agent, last_msg, messages, all_msgs, usage) do
    # No tool calls, just return the result
    updated_agent = %{agent | messages: messages ++ [last_msg]}
    {:ok, {last_msg, all_msgs, updated_agent, nil}, usage}
  end

  @doc """
  Processes tool calls by checking retry limits and executing the tools.
  """
  @spec process_tool_calls(t(), Message.t(), [Message.t()], Provider.usage()) ::
          {:ok, {Message.t(), [Message.t()], t(), list(tool_result()) | nil}, Provider.usage()}
  defp process_tool_calls(agent, last_msg, all_msgs, usage) do
    case check_max_failed_retries(agent, last_msg.tool_calls) do
      {:ok} ->
        execute_and_update_agent(agent, last_msg, all_msgs, usage)

      {:error, reason} ->
        error_message = %Message{
          role: "assistant",
          content: "Could not execute tool call, reached max failed retries for last tool call.\nError details:\n#{inspect(reason)}"
        }
        updated_messages = all_msgs ++ [error_message]
        updated_agent = %{agent | messages: updated_messages}
        {:ok, {last_msg, updated_messages, updated_agent, nil}, usage}
    end
  end

  @doc """
  Executes tool calls and updates the agent with results.
  """
  @spec execute_and_update_agent(t(), Message.t(), [Message.t()], Provider.usage()) ::
          {:ok, {Message.t(), [Message.t()], t(), list(tool_result())}, Provider.usage()}
  defp execute_and_update_agent(agent, last_msg, all_msgs, usage) do
    tool_result_messages = execute_tool_calls(agent.tools, last_msg.tool_calls)
    updated_messages = all_msgs ++ tool_result_messages

    tool_results =
      tool_result_messages
      |> Enum.map(fn message ->
        tool_call = find_matching_tool_call(last_msg.tool_calls, message.tool_call_id)
        {tool_call, message, message.content}
      end)

    updated_tool_history = update_tool_history(agent.tool_history, tool_results)
    updated_agent = %{agent |
      messages: updated_messages,
      tool_history: updated_tool_history
    }

    {:ok, {last_msg, updated_messages, updated_agent, tool_results}, usage}
  end

  @doc """
  Finds the tool call that matches the given tool call ID.
  """
  @spec find_matching_tool_call(list(Message.tool_call()), String.t()) :: Message.tool_call() | nil
  defp find_matching_tool_call(tool_calls, tool_call_id) do
    Enum.find_value(tool_calls, fn tc ->
      if tc.id == tool_call_id, do: tc, else: nil
    end)
  end

  @doc """
  Checks if max_failed_retries is exceeded for any tool calls.
  Returns :ok if we can proceed, or :error if max_failed_retries is exceeded.
  """
  @spec check_max_failed_retries(t(), list(Message.tool_call())) ::
          {:ok} | {:error, term()}
  defp check_max_failed_retries(%__MODULE__{max_failed_retries: nil} = _agent, tool_calls) do
    # If max_failed_retries is not set, we can always proceed
    {:ok, tool_calls}
  end

  defp check_max_failed_retries(%__MODULE__{} = agent, tool_calls) do
    # Check each tool call to see if it exceeds max_failed_retries
    Enum.reduce_while(tool_calls, {:ok, []}, fn tool_call, acc ->
      case acc do
        {:ok, _} ->
          tool_name = tool_call.function.name
          arguments = Jason.decode!(tool_call.function.arguments)

          if exceeded_failed_retries?(agent, tool_name, arguments) do
            {:halt, {:error, "Max failed retries exceeded for tool #{tool_name}"}}
          else
            {:continue, {:ok}} # Continue checking other tool calls
          end
        {:error, _, _} ->
          {:halt, acc}
      end
    end)
  end

  @doc """
  Updates the tool history with new tool results.
  """
  @spec update_tool_history([Tool.ToolHistory.t()], list({Message.tool_call(), Message.t(), map()})) ::
          [Tool.ToolHistory.t()]
  def update_tool_history(history, tool_results) do
    Enum.reduce(tool_results, history, fn {tool_call, _tool_result, result}, acc ->
      tool_history_entry = %Tool.ToolHistory{
        tool_name: tool_call.function.name,
        input_parameters: Jason.decode!(tool_call.function.arguments),
        output: result,
        timestamp: DateTime.utc_now()
      }
      [tool_history_entry | acc]
    end)
  end

  @doc """
  Checks if max_failed_retries is exceeded for a tool call.
  """
  @spec exceeded_failed_retries?(t(), String.t(), map()) :: boolean()
  defp exceeded_failed_retries?(%__MODULE__{} = agent, tool_name, arguments) do
    if agent.max_failed_retries == 0 do
      false
    else
      agent.tool_history
      |> Enum.filter(fn entry ->
        entry.tool_name == tool_name && entry.input_parameters == arguments && is_map_key(entry.output, :error)
      end)
      |> length() >= agent.max_failed_retries
    end
  end

  @spec build_messages(t(), Message.t() | String.t()) :: {:ok, list(Message.t())}
  defp build_messages(%__MODULE__{messages: messages}, %Message{} = user_prompt) do
    {:ok, messages ++ [user_prompt]}
  end

  defp build_messages(%__MODULE__{messages: messages}, user_prompt)
       when is_binary(user_prompt) do
    {:ok, messages ++ [Message.user(user_prompt)]}
  end

  @spec chat_completion(t(), list(Message.t())) ::
          {:ok, {Message.t(), [Message.t()]}, Provider.usage()} | {:error, term()}
  defp(chat_completion(agent, messages)) do
    Model.chat_completion(agent.model, messages, agent.tools)
  end

  @doc """
  Executes tool calls using the provided tools.
  Returns a list of tool result messages.
  """
  @spec execute_tool_calls([Tool.t()], list(Message.tool_call())) :: [Message.t()]
  defp execute_tool_calls(tools, tool_calls) do
    tool_calls
    |> Enum.flat_map(fn message ->
      Enum.map(message.tool_calls, fn tool_call ->
        tool_name = Map.get(tool_call, :function) |> Map.get(:name)
        tool = Enum.find(tools, fn t -> t.tool_name() == tool_name end)

        if tool == nil do
          Message.tool_result(Map.get(tool_call, :id), %{error: "Tool not found: #{tool_name}"})
        else
          arguments = Map.get(tool_call, :function) |> Map.get(:arguments) |> Jason.decode!()

          # Execute the tool with decoded arguments
          case tool.call(arguments) do
            {:ok, result} ->
              Message.tool_result(Map.get(tool_call, :id), result)

            {:error, error} ->
              Message.tool_result(Map.get(tool_call, :id), %{error: error})
          end
        end
      end)
    end)
  end

end
