defmodule Dantex.AgentTest do
  use ExUnit.Case, async: true
  alias Dantex.{Agent, Message}

  setup_all do
    # Set minimal config for tests that create agents
    Application.put_env(:dantex, :providers, %{
      openai: %{api_key: "test_key"}
    })
    
    :ok
  end

  describe "agent creation and configuration" do
    test "creates agent with basic configuration" do
      messages = [Message.system("You are a helpful assistant")]
      
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: messages,
        tools: [],
        max_failed_retries: 3
      )

      assert agent.model.model == "gpt-4o-mini"
      assert agent.messages == messages
      assert agent.tools == []
      assert agent.max_failed_retries == 3
      assert agent.tool_history == []
      assert is_binary(agent.context.id)
    end

    test "sets default values correctly" do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: []
      )

      assert agent.max_failed_retries == 0  # disabled by default
      assert agent.tools == []
      assert agent.tool_history == []
      assert agent.context != %{}
      assert is_binary(agent.context.id)
    end

    test "preserves custom context" do
      custom_context = %{user_id: 123, session: "abc"}
      
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini", 
        messages: [],
        context: custom_context
      )

      assert agent.context.user_id == 123
      assert agent.context.session == "abc"
      assert is_binary(agent.context.id)  # ID should be auto-generated
    end
  end

  describe "agent tool management" do
    test "adds tools to existing agent" do
      defmodule TestTool1 do
        use Dantex.Tool
        
        tool :test_action,
          description: "Test tool",
          input: [value: :integer] do
          _context_id = context.id
          "result: #{params.value}"
        end
      end

      defmodule TestTool2 do
        use Dantex.Tool
        
        tool :another_action,
          description: "Another test tool", 
          input: [name: :string] do
          _context_id = context.id
          "hello #{params.name}"
        end
      end

      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [],
        tools: [TestTool1]
      )

      assert length(agent.tools) == 1

      updated_agent = Agent.add_tools(agent, [TestTool2])
      assert length(updated_agent.tools) == 2
    end

    test "sets tool adapter" do
      alias Dantex.Tool.OpenAIAdapter

      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: []
      )

      updated_agent = Agent.set_tool_adapter(agent, OpenAIAdapter)
      assert updated_agent.tool_adapter == OpenAIAdapter
    end

    test "sets max failed retries" do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: []
      )

      updated_agent = Agent.set_max_failed_retries(agent, 5)
      assert updated_agent.max_failed_retries == 5

      updated_agent = Agent.set_max_failed_retries(agent, nil)
      assert updated_agent.max_failed_retries == nil
    end
  end

  describe "tool history management" do
    test "updates tool history correctly" do
      # Create sample tool results
      tool_call = %{
        id: "call_1",
        function: %{
          name: "test_tool",
          arguments: ~s({"value": 42})
        }
      }

      tool_result_message = Message.tool_result("call_1", "success")
      result_data = %{status: "ok", value: 42}

      tool_results = [{tool_call, tool_result_message, result_data}]

      history = Agent.update_tool_history([], tool_results)

      assert length(history) == 1
      
      entry = List.first(history)
      assert entry.tool_name == "test_tool"
      assert entry.input_parameters == %{"value" => 42}
      assert entry.output == %{status: "ok", value: 42}
      assert %DateTime{} = entry.timestamp
    end

    test "accumulates multiple tool history entries" do
      tool_call1 = %{
        id: "call_1",
        function: %{name: "tool1", arguments: ~s({"x": 1})}
      }
      
      tool_call2 = %{
        id: "call_2", 
        function: %{name: "tool2", arguments: ~s({"y": 2})}
      }

      result1 = {tool_call1, Message.tool_result("call_1", "result1"), "result1"}
      result2 = {tool_call2, Message.tool_result("call_2", "result2"), "result2"}

      history = []
      history = Agent.update_tool_history(history, [result1])
      history = Agent.update_tool_history(history, [result2])

      assert length(history) == 2
      
      # History is accumulated with newest first
      assert List.first(history).tool_name == "tool2"
      assert List.last(history).tool_name == "tool1"
    end
  end

  describe "sub-agent functionality" do
    test "creates agent with sub-agents" do
      # Create sub-agents
      code_reviewer = Agent.new(
        provider: :openai,
        model: "gpt-4o",
        messages: [Message.system("You are a code reviewer")]
      )
      
      debugger = Agent.new(
        provider: :openai,
        model: "gpt-4o",
        messages: [Message.system("You are a debugger")]
      )
      
      # Create main agent with sub-agents
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [Message.system("You are a helpful assistant")],
        sub_agents: %{
          "code_reviewer" => code_reviewer,
          "debugger" => debugger
        }
      )
      
      assert map_size(agent.sub_agents) == 2
      assert Map.has_key?(agent.sub_agents, "code_reviewer")
      assert Map.has_key?(agent.sub_agents, "debugger")
      
      # Should include SubAgentTool since we have sub_agents
      sub_agent_tool = Enum.find(agent.tools, fn tool -> 
        tool == Dantex.Tool.SubAgentTool
      end)
      assert sub_agent_tool != nil
    end
    
    test "agent without sub-agents has empty sub_agents map" do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: []
      )
      
      assert agent.sub_agents == %{}
      
      # Should not include SubAgentTool since no sub_agents
      sub_agent_tool = Enum.find(agent.tools, fn tool -> 
        tool == Dantex.Tool.SubAgentTool
      end)
      assert sub_agent_tool == nil
    end
    
    test "SubAgentTool validates input schema" do
      # This tests that the tool is properly defined
      assert Dantex.Tool.SubAgentTool.tool_name() == "delegate_to_sub_agent"
      assert is_binary(Dantex.Tool.SubAgentTool.tool_description())
    end
  end

  # Simple integration test that doesn't require mocking
  describe "telemetry metadata" do
    test "Message.to_telemetry converts message correctly" do
      message = Message.assistant("Hello world")
      telemetry_data = Message.to_telemetry(message)

      assert telemetry_data.role == "assistant"
      assert telemetry_data.content == "Hello world"
      assert telemetry_data.has_tool_calls == false
      assert telemetry_data.tool_calls_count == 0
      assert telemetry_data.tool_calls == nil
      assert telemetry_data.tool_call_id == nil
    end

    test "Message.to_telemetry handles tool calls" do
      tool_calls = [
        %{id: "call_1", function: %{name: "test_tool", arguments: "{}"}},
        %{id: "call_2", function: %{name: "other_tool", arguments: "{}"}}
      ]

      message = %Message{
        role: "assistant",
        content: "I'll use some tools",
        tool_calls: tool_calls
      }

      telemetry_data = Message.to_telemetry(message)

      # Expected telemetry format flattens the tool calls structure
      expected_telemetry_tool_calls = [
        %{id: "call_1", name: "test_tool", arguments: %{}},
        %{id: "call_2", name: "other_tool", arguments: %{}}
      ]

      assert telemetry_data.role == "assistant"
      assert telemetry_data.content == "I'll use some tools"
      assert telemetry_data.has_tool_calls == true
      assert telemetry_data.tool_calls_count == 2
      assert telemetry_data.tool_calls == expected_telemetry_tool_calls
      assert telemetry_data.tool_call_id == nil
    end
  end

  describe "agentic loop methods" do
    test "add_message/2 adds message to conversation" do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [Message.system("You are helpful")]
      )

      assert length(Agent.get_messages(agent)) == 1

      agent = Agent.add_message(agent, Message.user("Hello"))
      messages = Agent.get_messages(agent)

      assert length(messages) == 2
      assert List.last(messages).role == "user"
      assert List.last(messages).content == "Hello"
    end

    test "get_messages/1 returns conversation history" do
      messages = [
        Message.system("You are helpful"),
        Message.user("Hello"),
        Message.assistant("Hi there!")
      ]

      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: messages
      )

      retrieved_messages = Agent.get_messages(agent)
      assert retrieved_messages == messages
      assert length(retrieved_messages) == 3
    end

    test "has_tool_calls?/1 returns false when no messages" do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: []
      )

      refute Agent.has_tool_calls?(agent)
    end

    test "has_tool_calls?/1 returns false when last message has no tool calls" do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [
          Message.system("You are helpful"),
          Message.user("Hello"),
          Message.assistant("Hi there!")
        ]
      )

      refute Agent.has_tool_calls?(agent)
    end

    test "has_tool_calls?/1 returns true when last message has tool calls" do
      tool_calls = [
        %{id: "call_1", function: %{name: "test_tool", arguments: "{}"}}
      ]

      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [
          Message.system("You are helpful"),
          %Message{role: "assistant", content: "Using a tool", tool_calls: tool_calls}
        ]
      )

      assert Agent.has_tool_calls?(agent)
    end

    test "execute_tools/1 returns agent unchanged when no tool calls" do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: [
          Message.system("You are helpful"),
          Message.assistant("Hello")
        ]
      )

      result_agent = Agent.execute_tools(agent)
      assert result_agent == agent
      assert length(Agent.get_messages(result_agent)) == 2
    end

    test "execute_tools/1 returns agent unchanged when no messages" do
      agent = Agent.new(
        provider: :openai,
        model: "gpt-4o-mini",
        messages: []
      )

      result_agent = Agent.execute_tools(agent)
      assert result_agent == agent
    end
  end
end