defmodule Dantex.Agent do
  @moduledoc """
  Agents are containers that group model, messages and tooling.

  They can track the history of tool calls and enforce limits on the number of failed
  retries for a given tool and set of arguments.

  ## Sub-Agent Support

  Agents can have specialized sub-agents that handle specific types of tasks.
  This enables hierarchical problem-solving where complex tasks can be delegated
  to experts with specialized knowledge and tools.

  ### Creating Agents with Sub-Agents

      # Create specialized sub-agents
      code_reviewer = Agent.new(
        provider: :anthropic,
        model: "claude-3-opus",
        messages: [Message.system("You are an expert code reviewer")]
      )

      debugger = Agent.new(
        provider: :openai,
        model: "gpt-4o",
        messages: [Message.system("You are a debugging specialist")]
      )

      # Create main agent with sub-agents
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [Message.system("You coordinate specialized tasks")],
        sub_agents: %{
          "code_reviewer" => code_reviewer,
          "debugger" => debugger
        }
      )

  ### How Sub-Agent Delegation Works

  1. When an agent has sub-agents, a `SubAgentTool` is automatically added to its tools
  2. The LLM can use this tool to delegate tasks: `delegate_to_sub_agent`
  3. Sub-agents run in their own context with their specialized prompts and tools
  4. Results are returned to the main agent to continue the conversation

  ## Example

      alias Dantex.{Agent, Message}

      messages = [
        "You multiple everything with 2" |> Message.system()
      ]

      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: messages
      )

      {:ok, response, updated_agent} = Agent.run(agent, "What is 2+2?")

      # Define a tool
      defmodule DiceTool do
        use Dantex.Tool

        tool :roll_die,
          description: "Roll a six-sided die and return the result",
          input: [sides: [:integer, default: 6]] do

          {:ok, %{result: Enum.random(1..params.sides)}}
        end
      end

      # Create an agent with tools
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        tools: [DiceTool],
        max_failed_retries: 3
      )

      # Run the agent
      {:ok, response, updated_agent} = Agent.run(agent, "Roll the dice")
  """

  alias Dantex.{Tool, Model, Message, Provider}
  alias Dantex.Tool.{OpenAIAdapter, ToolAdapter, MCP}

  @type t :: %__MODULE__{
          model: Model.t(),
          tools: [Tool.t()],
          messages: [Message.t()],
          tool_history: [Tool.ToolHistory.t()],
          max_failed_retries: non_neg_integer() | nil,
          tool_adapter: module(),
          context: map(),
          sub_agents: %{String.t() => t()},
          timeout: non_neg_integer() | nil
        }

  defstruct [
    :model,
    :tools,
    :messages,
    :tool_history,
    :max_failed_retries,
    :tool_adapter,
    :context,
    :sub_agents,
    :timeout
  ]

  @doc """
  Creates a new agent with the given configuration.

  ## Options

    * `:provider` - The AI model provider to use (required)
    * `:model` - The AI model to use (required)
    * `:messages` - A list of prompt messages (required)
    * `:tools` - List of tool modules to use (default: [])
    * `:sub_agents` - Map of sub-agent names to Agent instances (default: %{})
    * `:max_failed_retries` - The maximum number of failed retries for a tool call with the same arguments (optional, default: nil)
    * `:tool_adapter` - The tool adapter module to use (default: OpenAIAdapter - uses OpenAI function calling spec)
    * `:context` - Map of context data passed to tools (default: %{})
    * `:timeout` - Request timeout in milliseconds (optional, uses provider defaults if not specified)

  ## Example

      Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [Message{content: "You are a helpful assistant", role: "system"}],
        tools: [WeatherTool, TimeTool],
        sub_agents: %{
          "code_reviewer" => Agent.new(provider: :anthropic, model: "claude-3-opus", tools: [CodeAnalysisTool]),
          "debugger" => Agent.new(provider: :openai, model: "gpt-4o", tools: [DebugTool])
        },
        max_failed_retries: 3,
        tool_adapter: OpenAIAdapter,
        context: %{weather_api_key: "your_key", user_id: 123},
        timeout: 60_000  # 60 seconds
      )
  """
  require Logger

  @spec new([
          {:provider, atom()}
          | {:model, String.t()}
          | {:messages, [Message.t()]}
          | {:tools, [Tool.t()]}
          | {:sub_agents, %{String.t() => t()}}
          | {:mcp_clients, [module()]}
          | {:mcp_filters, map()}
          | {:context, map()}
          | {:max_failed_retries, non_neg_integer()}
          | {:tool_adapter, ToolAdapter.t()}
          | {:timeout, non_neg_integer()}
        ]) ::
          t()
  def new(opts) do
    provider = Keyword.get(opts, :provider, :openai)
    model = Keyword.get(opts, :model, "gpt-4o-mini")
    tools = Keyword.get(opts, :tools, [])
    sub_agents = Keyword.get(opts, :sub_agents, %{})
    mcp_clients = Keyword.get(opts, :mcp_clients, [])
    mcp_filters = Keyword.get(opts, :mcp_filters, %{})
    messages = Keyword.get(opts, :messages, [])
    # 0, equals disabled
    max_failed_retries = Keyword.get(opts, :max_failed_retries, 0)
    tool_adapter = Keyword.get(opts, :tool_adapter, OpenAIAdapter)
    context = Keyword.get(opts, :context, %{})
    timeout = Keyword.get(opts, :timeout, nil)

    # Generate agent ID if not provided
    context_with_id =
      case Map.get(context, :id) do
        nil -> Map.put(context, :id, UUID.uuid4())
        _existing_id -> context
      end

    mcp_tools = discover_mcp_tools(mcp_clients, mcp_filters)

    # Add SubAgentTool if there are sub_agents, so LLM can delegate to them
    sub_agent_tools = if map_size(sub_agents) > 0, do: [Dantex.Tool.SubAgentTool], else: []

    all_tools = tools ++ mcp_tools ++ sub_agent_tools

    %__MODULE__{
      model: Model.new(provider, model),
      messages: messages,
      tools: all_tools,
      tool_history: [],
      max_failed_retries: max_failed_retries,
      tool_adapter: tool_adapter,
      context: context_with_id,
      sub_agents: sub_agents,
      timeout: timeout
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

  @doc """
  Executes a single iteration of the conversation loop.

  This performs one complete cycle:
  1. Sends current messages to the AI provider
  2. Receives and processes the response
  3. Extracts any tool calls from the response
  4. Returns the updated agent with the new message added

  Use this method to build custom agentic loops with full control over
  when to continue, stop, or add custom logic between iterations.

  ## Example

      agent = Agent.new(provider: :openai, model: "gpt-4", tools: [MyTool])
      agent = Agent.add_message(agent, Message.user("Hello"))

      # Execute one step
      {:ok, response_message, updated_agent} = Agent.step(agent)

      # Check if more iterations needed
      if Agent.has_tool_calls?(updated_agent) do
        updated_agent = Agent.execute_tools(updated_agent)
        # Continue with more steps...
      end
  """
  @spec step(t()) :: {:ok, Message.t(), t()} | {:error, term()}
  def step(%__MODULE__{} = agent) do
    with {:ok, {last_msg, _}, _} <- chat_completion(agent, agent.messages),
         {:ok, processed_msg} <- agent.tool_adapter.extract_tool_calls(last_msg) do
      {:ok, final_msg, updated_agent} = process_message(agent, processed_msg)
      {:ok, final_msg, updated_agent}
    else
      {:rate_limit, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute_tool_calls(%__MODULE__{} = agent) do
    message = List.last(agent.messages)

    case process_message(agent, message) do
      {:ok, message, updated_agent} ->
        {:ok, message, updated_agent}

      {:error, reason} ->
        error_message = %Message{
          role: "assistant",
          content: "Error executing tool calls: #{inspect(reason)}"
        }

        updated_messages = agent.messages ++ [error_message]
        updated_agent = %{agent | messages: updated_messages}
        {:ok, error_message, updated_agent}

      _ ->
        {:ok, message, agent}
    end
  end

  @doc """
  Adds a message to the agent's conversation history.

  ## Example

      agent = Agent.new(provider: :openai, model: "gpt-4")
      agent = Agent.add_message(agent, Message.user("What is 2+2?"))
      agent = Agent.add_message(agent, Message.assistant("2+2 equals 4"))
  """
  @spec add_message(t(), Message.t()) :: t()
  def add_message(%__MODULE__{} = agent, %Message{} = message) do
    %{agent | messages: agent.messages ++ [message]}
  end

  @doc """
  Returns the current conversation history.

  ## Example

      messages = Agent.get_messages(agent)
      IO.inspect(length(messages))  # Number of messages in conversation
  """
  @spec get_messages(t()) :: [Message.t()]
  def get_messages(%__MODULE__{} = agent) do
    agent.messages
  end

  @doc """
  Checks if the agent has pending tool calls that need to be executed.

  Returns true when the last message is an assistant message with tool_calls
  that haven't been executed yet.

  ## Example

      agent = Agent.step(agent)
      if Agent.has_pending_tool_calls?(agent) do
        agent = Agent.execute_tools(agent)
      end
  """
  @spec has_pending_tool_calls?(t()) :: boolean()
  def has_pending_tool_calls?(%__MODULE__{messages: messages}) when length(messages) > 0 do
    case List.last(messages) do
      %{role: "assistant"} = last_message -> message_has_tool_calls?(last_message)
      _ -> false
    end
  end

  def has_pending_tool_calls?(%__MODULE__{}), do: false

  @doc """
  Checks if the agent has completed tool calls that should continue the conversation.

  Returns true when we have tool result messages following an assistant message,
  indicating tools have been executed and the conversation should continue.

  ## Example

      if Agent.has_completed_tool_calls?(agent) do
        # Continue conversation loop
        Agent.step(agent)
      end
  """
  @spec has_completed_tool_calls?(t()) :: boolean()
  def has_completed_tool_calls?(%__MODULE__{messages: messages}) when length(messages) >= 2 do
    last_message = List.last(messages)
    second_to_last = Enum.at(messages, -2)

    case {last_message, second_to_last} do
      {%{role: "tool"}, %{role: "assistant"}} -> true
      _ -> false
    end
  end

  def has_completed_tool_calls?(%__MODULE__{}), do: false

  @doc """
  Checks if the agent has tool calls in any state (pending or completed).

  Returns true when either:
  - There are pending tool calls that need execution
  - There are completed tool calls that should continue the conversation

  ## Example

      agent = Agent.step(agent)
      if Agent.has_tool_calls?(agent) do
        agent = Agent.execute_tools(agent)
      end
  """
  @spec has_tool_calls?(t()) :: boolean()
  def has_tool_calls?(%__MODULE__{} = agent) do
    has_pending_tool_calls?(agent) or has_completed_tool_calls?(agent)
  end

  @doc """
  Executes any pending tool calls from the last message and adds the results to the conversation.

  This method should be called after `step/1` when `has_tool_calls?/1` returns true.
  It will execute all tool calls from the last assistant message and add the tool
  result messages to the conversation history.

  ## Example

      agent = Agent.step(agent)
      if Agent.has_tool_calls?(agent) do
        agent = Agent.execute_tools(agent)
        # Tool results are now in the conversation
      end
  """
  @spec execute_tools(t()) :: t()
  def execute_tools(%__MODULE__{messages: messages} = agent) when length(messages) > 0 do
    last_message = List.last(messages)

    if message_has_tool_calls?(last_message) do
      {:ok, _final_msg, updated_agent} = process_tool_calls(agent, last_message)
      updated_agent
    else
      agent
    end
  end

  def execute_tools(%__MODULE__{} = agent), do: agent

  @max_iterations 50

  @spec run_conversation_loop(t(), [Message.t()], non_neg_integer()) ::
          {:ok, Message.t(), t()} | {:error, term()}
  defp run_conversation_loop(_agent, _messages, iteration) when iteration >= @max_iterations do
    {:error, "Maximum iterations (#{@max_iterations}) reached. Possible infinite loop detected."}
  end

  defp run_conversation_loop(agent, messages, iteration) do
    with {:ok, {last_msg, _}, _} <- chat_completion(agent, messages),
         {:ok, processed_msg} <- agent.tool_adapter.extract_tool_calls(last_msg) do
      {:ok, final_msg, updated_agent} = process_message(agent, processed_msg)

      if message_has_tool_calls?(final_msg) do
        run_conversation_loop(updated_agent, updated_agent.messages, iteration + 1)
      else
        {:ok, final_msg, updated_agent}
      end
    else
      {:rate_limit, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec message_has_tool_calls?(Message.t()) :: boolean()
  defp message_has_tool_calls?(%Message{tool_calls: tool_calls})
       when is_list(tool_calls) and length(tool_calls) > 0 do
    true
  end

  defp message_has_tool_calls?(_), do: false

  @spec process_message(t(), Message.t()) :: {:ok, Message.t(), t()}
  defp process_message(agent, %{tool_calls: tool_calls} = last_msg)
       when is_list(tool_calls) and length(tool_calls) > 0 do
    updated_agent = %{agent | messages: agent.messages ++ [last_msg]}
    process_tool_calls(updated_agent, last_msg)
  end

  defp process_message(agent, last_msg) do
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
          content:
            "Could not execute tool call, reached max failed retries for last tool call.\nError details:\n#{inspect(reason)}"
        }

        updated_messages = agent.messages ++ [error_message]
        updated_agent = %{agent | messages: updated_messages}
        {:ok, last_msg, updated_agent}
    end
  end

  @spec execute_and_update_agent(t(), Message.t()) :: {:ok, Message.t(), t()}
  defp execute_and_update_agent(agent, last_msg) do
    enhanced_context = Map.put(agent.context, :sub_agents, agent.sub_agents)

    tool_execution_results =
      execute_tool_calls(agent.tools, last_msg.tool_calls, enhanced_context)

    {tool_result_messages, original_results} = Enum.unzip(tool_execution_results)

    updated_messages = agent.messages ++ tool_result_messages

    tool_results =
      Enum.zip([last_msg.tool_calls, tool_result_messages, original_results])
      |> Enum.map(fn {tool_call, message, original_result} ->
        {tool_call, message, original_result}
      end)

    updated_tool_history = update_tool_history(agent.tool_history, tool_results)
    updated_agent = %{agent | messages: updated_messages, tool_history: updated_tool_history}

    {:ok, last_msg, updated_agent}
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
        # Continue checking other tool calls
        {:cont, acc}
      end
    end)
  end

  @doc """
  Updates the tool history with new tool results.
  """
  @spec update_tool_history(
          [Tool.ToolHistory.t()],
          list({Message.tool_call(), Message.t(), map()})
        ) ::
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
        entry.tool_name == tool_name &&
          entry.input_parameters == arguments &&
          is_map(entry.output) &&
          Map.has_key?(entry.output, :error)
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

  @spec chat_completion(t()) ::
          {:ok, {Message.t(), t()}} | {:error, term()}
  def chat_completion(%__MODULE__{} = agent) do
    case chat_completion(agent, agent.messages) do
      {:ok, {message, messages}, usage} ->
        if message_has_tool_calls?(message) do
          case agent.tool_adapter.extract_tool_calls(message) do
            {:ok, processed_msg} ->
              updated_messages = messages ++ [processed_msg]
              {:ok, {processed_msg, %{agent | messages: updated_messages}}, usage}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:ok, {message, %{agent | messages: messages ++ [message]}}, usage}
        end

      {:rate_limit, reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec chat_completion(t(), list(Message.t())) ::
          {:ok, {Message.t(), [Message.t()]}, Provider.usage()}
          | {:error, term()}
          | {:rate_limit, String.t()}
  defp(chat_completion(agent, messages)) do
    Model.chat_completion(agent.model, messages, agent.tools, agent.timeout)
  end

  @spec execute_tool_calls([Tool.t()], list(Message.tool_call()), map()) :: [{Message.t(), any()}]
  defp execute_tool_calls(tools, tool_calls, context) do
    tool_calls = if is_list(tool_calls), do: tool_calls, else: [tool_calls]

    tool_calls
    |> Enum.map(fn tool_call ->
      tool_name = Map.get(tool_call, :function) |> Map.get(:name)
      tool = Enum.find(tools, fn t -> t.tool_name() == tool_name end)

      {result_message, original_result} =
        if tool == nil do
          error_result = %{error: "Tool not found: #{tool_name}"}
          {Message.tool_result(Map.get(tool_call, :id), error_result), error_result}
        else
          arguments = Map.get(tool_call, :function) |> Map.get(:arguments) |> Jason.decode!()

          # Execute the tool with decoded arguments and context
          # Use string key to match the JSON-decoded arguments format
          params_with_context = Map.put(arguments, "context", context)

          case tool.call(params_with_context) do
            {:ok, tool_result} ->
              {Message.tool_result(Map.get(tool_call, :id), tool_result), tool_result}

            {:error, error} ->
              error_result = %{error: error}
              {Message.tool_result(Map.get(tool_call, :id), error_result), error_result}
          end
        end

      {result_message, original_result}
    end)
  end

  # MCP Support Functions

  # Discovers tools from MCP clients and applies filters.
  @spec discover_mcp_tools([module()], map()) :: [module()]
  defp discover_mcp_tools(mcp_clients, mcp_filters) when is_list(mcp_clients) do
    Enum.flat_map(mcp_clients, fn client_module ->
      case MCP.discover_tools(client_module, mcp_filters) do
        {:ok, mcp_tools} ->
          Logger.info(
            "Discovered #{length(mcp_tools)} tools from MCP client #{inspect(client_module)}"
          )

          mcp_tools

        {:error, reason} ->
          Logger.warning(
            "Failed to discover tools from MCP client #{inspect(client_module)}: #{inspect(reason)}"
          )

          []
      end
    end)
  end

  defp discover_mcp_tools([], _), do: []
end
