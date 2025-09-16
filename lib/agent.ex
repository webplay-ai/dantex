defmodule Dantex.Agent do
  @moduledoc """
  Agents are containers that group model, messages and tooling.

  They can track the history of tool calls and enforce limits on the number of failed
  retries for a given tool and set of arguments.

  ## Telemetry Events

  This module emits several telemetry events that can be used for observability,
  logging, debugging, and real-time UI updates:

  ### `[:dantex, :agent, :message]`
  Emitted for each message processed in the conversation loop.
  
  **Measurements:** `%{iteration: integer()}`
  **Metadata:** 
  ```elixir
  %{
    agent_id: String.t(),
    message: %{
      role: String.t(),
      content: String.t() | nil,
      has_tool_calls: boolean(),
      tool_calls_count: integer(),
      tool_calls: list() | nil,
      tool_call_id: String.t() | nil
    },
    timestamp: DateTime.t()
  }
  ```

  ### `[:dantex, :agent, :response]`
  Emitted when the agent provides a final response (no more tool calls).
  
  **Measurements:** `%{iteration: integer()}`
  **Metadata:**
  ```elixir
  %{
    agent_id: String.t(),
    final_message: %{
      role: String.t(),
      content: String.t() | nil,
      has_tool_calls: boolean(),
      tool_calls_count: integer(),
      tool_calls: list() | nil,
      tool_call_id: String.t() | nil
    },
    total_iterations: integer(),
    timestamp: DateTime.t()
  }
  ```

  ### `[:dantex, :agent, :tool_call_start]`
  Emitted when a tool call begins execution.
  
  **Measurements:** `%{}`
  **Metadata:**
  ```elixir
  %{
    agent_id: String.t(),
    tool_name: String.t(),
    tool_call_id: String.t(),
    arguments: String.t(), # JSON string
    timestamp: DateTime.t()
  }
  ```

  ### `[:dantex, :agent, :tool_call_complete]`
  Emitted when a tool call completes.
  
  **Measurements:** `%{}`
  **Metadata:**
  ```elixir
  %{
    agent_id: String.t(),
    tool_name: String.t(),
    tool_call_id: String.t(),
    result: any(),
    success: boolean(),
    timestamp: DateTime.t()
  }
  ```

  ## Custom Telemetry Handlers

  You can attach custom handlers to these events for logging, metrics, or UI updates:

  ```elixir
  # Logging handler
  :telemetry.attach("my-logger", [:dantex, :agent, :message], fn _name, _measurements, metadata, _config ->
    Logger.info("Agent message received", metadata)
  end, nil)

  # LiveView/PubSub handler
  :telemetry.attach("my-liveview", [:dantex, :agent, :message], fn _name, _measurements, metadata, _config ->
    Phoenix.PubSub.broadcast(MyApp.PubSub, "agent:\#{metadata.agent_id}", {:agent_message, metadata})
  end, nil)

  # Metrics handler
  :telemetry.attach("my-metrics", [:dantex, :agent, :tool_call_complete], fn _name, _measurements, metadata, _config ->
    :telemetry.execute([:my_app, :tool_calls], %{count: 1}, %{
      tool_name: metadata.tool_name,
      success: metadata.success
    })
  end, nil)
  ```

  Future considerations:
  - How about if agents could decide to use different LLMs and switch from model in function tool calling theirselves? We just have to move the model to the run function instead. That would mean an agent is nothing more then a bunch of messages. You can have replace the system prompt.

  ## Example

      alias Dantex.{Agent, Message}

      messages = [
        "You multiple everythign with 2" |> Message.system()
      ]

      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: messages
      )

      {:ok, {response, agent}} = Agent.run(agent, "What is 2+2?")

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
        tools: [DiceTool], // optional
        max_failed_retries: 3 // optional
      )

      # Run the agent
      {:ok, response, agent} = Agent.run(agent, "Roll the dice")
  """

  alias Dantex.{Tool, Model, Message, Provider}
  alias Dantex.Tool.{OpenAIAdapter, ToolAdapter}

  @type t :: %__MODULE__{
          model: Model.t(),
          tools: [Tool.t()],
          messages: [Message.t()],
          tool_history: [Tool.ToolHistory.t()],
          max_failed_retries: non_neg_integer() | nil,
          tool_adapter: module(),
          context: map()
        }

  defstruct [
    :model,
    :tools,
    :messages,
    :tool_history,
    :max_failed_retries,
    :tool_adapter,
    :context
  ]

  @doc """
  Creates a new agent with the given configuration.

  ## Options

    * `:provider` - The AI model provider to use (required)
    * `:model` - The AI model to use (required)
    * `:messages` - A list of prompt messages (required)
    * `:tools` - List of tool modules to use (default: [])
    * `:max_failed_retries` - The maximum number of failed retries for a tool call with the same arguments (optional, default: nil)
    * `:tool_adapter` - The tool adapter module to use (default: OpenAIAdapter - uses OpenAI function calling spec)
    * `:context` - Map of context data passed to tools (default: %{})

  ## Example

      Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [Message{content: "You are a helpful assistant", role: "system"}],
        tools: [WeatherTool, TimeTool],
        max_failed_retries: 3,
        tool_adapter: OpenAIAdapter,
        context: %{weather_api_key: "your_key", user_id: 123}
      )
  """
  require Logger

  @spec new([
          {:provider, atom()}
          | {:model, String.t()}
          | {:messages, [Message.t()]}
          | {:tools, [Tool.t()]}
          | {:context, map()}
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
    context = Keyword.get(opts, :context, %{})

    # Generate agent ID if not provided
    context_with_id = case Map.get(context, :id) do
      nil -> Map.put(context, :id, UUID.uuid4())
      _existing_id -> context
    end
    %__MODULE__{
      model: Model.new(provider, model),
      messages: messages,
      tools: tools,
      tool_history: [],
      max_failed_retries: max_failed_retries,
      tool_adapter: tool_adapter,
      context: context_with_id
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
      agent = Agent.set_tool_adapter(agent, Dantex.Tool.OpenAIAdapter)
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
     d. Continue the conversation loop until no more tool calls
  5. Return with updated agent state, history and messages

  The conversation loop continues until the LLM provides a final response with no tool calls,
  with a maximum of 50 iterations to prevent infinite loops.
  """
  @spec run(t(), Message.t() | String.t()) :: {:ok, Message.t(), t()} | {:error, term()}
  def run(%__MODULE__{} = agent, message) do
    with {:ok, messages} <- build_messages(agent, message) do
      run_conversation_loop(agent, messages, 0)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @max_iterations 50

  @spec run_conversation_loop(t(), [Message.t()], non_neg_integer()) :: {:ok, Message.t(), t()} | {:error, term()}
  defp run_conversation_loop(_agent, _messages, iteration) when iteration >= @max_iterations do
    {:error, "Maximum iterations (#{@max_iterations}) reached. Possible infinite loop detected."}
  end

  defp run_conversation_loop(agent, messages, iteration) do
    with {:ok, {last_msg, _}, _} <- chat_completion(agent, messages),
         {:ok, processed_msg} <- agent.tool_adapter.extract_tool_calls(last_msg) do
      
      # Emit telemetry event for the processed message
      :telemetry.execute([:dantex, :agent, :message], %{iteration: iteration}, %{
        agent_id: agent.context.id,
        message: Message.to_telemetry(processed_msg),
        timestamp: DateTime.utc_now()
      })
      
      {:ok, final_msg, updated_agent} = process_message(agent, processed_msg)
      
      # Check if the message has tool calls - if so, continue the loop
      if has_tool_calls?(final_msg) do
        run_conversation_loop(updated_agent, updated_agent.messages, iteration + 1)
      else
        # Emit final response telemetry event
        :telemetry.execute([:dantex, :agent, :response], %{iteration: iteration}, %{
          agent_id: agent.context.id,
          final_message: Message.to_telemetry(final_msg),
          total_iterations: iteration + 1,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, final_msg, updated_agent}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec has_tool_calls?(Message.t()) :: boolean()
  defp has_tool_calls?(%Message{tool_calls: tool_calls}) when is_list(tool_calls) and length(tool_calls) > 0 do
    true
  end
  
  defp has_tool_calls?(_), do: false
  @spec process_message(t(), Message.t()) :: {:ok, Message.t(), t()}
  defp process_message(agent, %{tool_calls: tool_calls} = last_msg)
       when is_list(tool_calls) and length(tool_calls) > 0 do
    # Add the assistant message with tool calls to the agent messages first
    updated_agent = %{agent | messages: agent.messages ++ [last_msg]}
    process_tool_calls(updated_agent, last_msg)
  end

  defp process_message(agent, last_msg) do
    # No tool calls, just return the result
    updated_agent = %{agent | messages: agent.messages ++ [last_msg]}
    {:ok, last_msg, updated_agent}
  end

  @spec process_tool_calls(t(), Message.t()) :: {:ok, Message.t(), t()}
  defp process_tool_calls(agent, last_msg) do
    case check_max_failed_retries(agent, last_msg.tool_calls) do
      {:ok} ->
        execute_and_update_agent(agent, last_msg)

      {:error, reason} ->
        error_message = %Message{
          role: "assistant",
          content: "Could not execute tool call, reached max failed retries for last tool call.\nError details:\n#{inspect(reason)}"
        }
        updated_messages = agent.messages ++ [error_message]
        updated_agent = %{agent | messages: updated_messages}
        {:ok, last_msg, updated_agent}
    end
  end

  @spec execute_and_update_agent(t(), Message.t()) :: {:ok, Message.t(), t()}
  defp execute_and_update_agent(agent, last_msg) do
    tool_result_messages = execute_tool_calls(agent.tools, last_msg.tool_calls, agent.context)
    # Only add tool result messages since assistant message was already added
    updated_messages = agent.messages ++ tool_result_messages

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

    {:ok, last_msg, updated_agent}
  end

  @spec find_matching_tool_call(list(Message.tool_call()), String.t()) :: Message.tool_call() | nil
  defp find_matching_tool_call(tool_calls, tool_call_id) do
    Enum.find_value(tool_calls, fn tc ->
      if tc.id == tool_call_id, do: tc, else: nil
    end)
  end

  @spec check_max_failed_retries(t(), list(Message.tool_call())) ::
          {:ok} | {:error, term()}
  defp check_max_failed_retries(%__MODULE__{max_failed_retries: nil} = _agent, _tool_calls) do
    # If max_failed_retries is not set, we can always proceed
    {:ok}
  end

  defp check_max_failed_retries(%__MODULE__{} = _agent, []) do
    # If there are no tool calls, we can proceed
    {:ok}
  end

  defp check_max_failed_retries(%__MODULE__{} = agent, tool_calls) do
    # Check each tool call to see if it exceeds max_failed_retries
    Enum.reduce_while(tool_calls, {:ok}, fn tool_call, acc ->
      tool_name = tool_call.function.name
      arguments = Jason.decode!(tool_call.function.arguments)

      if exceeded_failed_retries?(agent, tool_name, arguments) do
        {:halt, {:error, "Max failed retries exceeded for tool #{tool_name}"}}
      else
        {:cont, acc} # Continue checking other tool calls
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

  @spec execute_tool_calls([Tool.t()], list(Message.tool_call()), map()) :: [Message.t()]
  defp execute_tool_calls(tools, tool_calls, context) do
    tool_calls = if is_list(tool_calls), do: tool_calls, else: [tool_calls]
    tool_calls
    |> Enum.map(fn tool_call ->
      tool_name = Map.get(tool_call, :function) |> Map.get(:name)
      tool = Enum.find(tools, fn t -> t.tool_name() == tool_name end)
      # Emit telemetry event for tool execution start
      :telemetry.execute([:dantex, :agent, :tool_call_start], %{}, %{
        agent_id: context.id,
        tool_name: tool_name,
        tool_call_id: Map.get(tool_call, :id),
        arguments: Map.get(tool_call, :function) |> Map.get(:arguments),
        timestamp: DateTime.utc_now()
      })
      
      result = if tool == nil do
        Message.tool_result(Map.get(tool_call, :id), %{error: "Tool not found: #{tool_name}"})
      else
        arguments = Map.get(tool_call, :function) |> Map.get(:arguments) |> Jason.decode!()

        # Execute the tool with decoded arguments and context
        # Use string key to match the JSON-decoded arguments format
        params_with_context = Map.put(arguments, "context", context)
        case tool.call(params_with_context) do
          {:ok, tool_result} ->
            Message.tool_result(Map.get(tool_call, :id), tool_result)

          {:error, error} ->
            Message.tool_result(Map.get(tool_call, :id), %{error: error})
        end
      end
      
      # Emit telemetry event for tool execution completion
      :telemetry.execute([:dantex, :agent, :tool_call_complete], %{}, %{
        agent_id: context.id,
        tool_name: tool_name,
        tool_call_id: Map.get(tool_call, :id),
        result: result.content,
        success: not Map.has_key?(result.content, :error),
        timestamp: DateTime.utc_now()
      })
      
      result
    end)
  end

end
