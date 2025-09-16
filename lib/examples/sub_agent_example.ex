defmodule Dantex.Examples.SubAgentExample do
  @moduledoc """
  Example demonstrating sub-agent functionality in Dantex.
  
  This example shows how to create a hierarchical agent system where
  a main agent can delegate tasks to specialized sub-agents.
  """
  
  alias Dantex.{Agent, Message}
  
  def run_example do
    # Create specialized sub-agents
    code_reviewer = Agent.new(
      provider: :openai,
      model: "gpt-4o",
      messages: [
        Message.system("""
        You are an expert code reviewer. Your job is to:
        1. Analyze code for bugs, security issues, and best practices
        2. Provide specific, actionable feedback
        3. Suggest improvements with examples
        4. Focus on code quality and maintainability
        """)
      ]
    )
    
    debugger = Agent.new(
      provider: :openai,
      model: "gpt-4o-mini",
      messages: [
        Message.system("""
        You are a debugging specialist. Your job is to:
        1. Analyze error messages and stack traces
        2. Identify root causes of bugs
        3. Suggest specific fixes
        4. Provide step-by-step debugging strategies
        """)
      ]
    )
    
    data_analyst = Agent.new(
      provider: :openai,
      model: "gpt-4o",
      messages: [
        Message.system("""
        You are a data analysis expert. Your job is to:
        1. Analyze data patterns and trends
        2. Generate insights and recommendations
        3. Create data visualizations when appropriate
        4. Explain statistical concepts clearly
        """)
      ]
    )
    
    # Create main agent with sub-agents
    main_agent = Agent.new(
      provider: :openai,
      model: "gpt-4o-mini",
      messages: [
        Message.system("""
        You are a helpful AI assistant that coordinates a team of specialists.
        When you receive tasks that require specialized expertise, you should
        delegate them to the appropriate sub-agent using the delegate_to_sub_agent tool.
        
        Available sub-agents:
        - code_reviewer: For code analysis, reviews, and quality assessment
        - debugger: For troubleshooting, error analysis, and bug fixes
        - data_analyst: For data analysis, insights, and statistical work
        
        Always consider whether a task would benefit from specialized expertise
        before handling it yourself.
        """)
      ],
      sub_agents: %{
        "code_reviewer" => code_reviewer,
        "debugger" => debugger,
        "data_analyst" => data_analyst
      }
    )
    
    IO.puts("🤖 Sub-Agent Example - Agent created with #{map_size(main_agent.sub_agents)} sub-agents")
    IO.puts("Available sub-agents: #{Map.keys(main_agent.sub_agents) |> Enum.join(", ")}")
    IO.puts("Tools available: #{length(main_agent.tools)}")
    IO.puts("")
    
    # Example 1: Code review task
    IO.puts("📝 Example 1: Code Review Task")
    code_task = """
    Please review this Python function for issues:
    
    def calculate_total(items):
        total = 0
        for item in items:
            total += item['price'] * item['quantity']
        return total
    """
    
    IO.puts("Task: #{code_task}")
    
    case Agent.run(main_agent, code_task) do
      {:ok, response, _updated_agent} ->
        IO.puts("Response: #{response.content}")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    IO.puts("")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("")
    
    # Example 2: Debugging task
    IO.puts("🐛 Example 2: Debugging Task")
    debug_task = """
    I'm getting this error in my Elixir application:
    
    ** (ArgumentError) argument error
        :erlang.atom_to_binary(nil, :utf8)
        (myapp 1.0.0) lib/myapp/user.ex:23: MyApp.User.format_name/1
    
    The function looks like this:
    def format_name(user) do
      "\#{user.first_name} \#{user.last_name}" |> String.upcase()
    end
    
    Can you help me debug this?
    """
    
    IO.puts("Task: #{debug_task}")
    
    case Agent.run(main_agent, debug_task) do
      {:ok, response, _updated_agent} ->
        IO.puts("Response: #{response.content}")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    IO.puts("")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("")
    
    # Example 3: Data analysis task
    IO.puts("📊 Example 3: Data Analysis Task")
    data_task = """
    I have sales data showing a 15% increase in Q1, 8% decrease in Q2, 
    22% increase in Q3, and 5% increase in Q4. What trends can you identify 
    and what recommendations would you make for the next year?
    """
    
    IO.puts("Task: #{data_task}")
    
    case Agent.run(main_agent, data_task) do
      {:ok, response, _updated_agent} ->
        IO.puts("Response: #{response.content}")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    IO.puts("")
    IO.puts("✅ Sub-agent example completed!")
  end
  
  def simple_delegation_example do
    # Simple example showing direct delegation to a sub-agent.
    
    # Create a simple sub-agent
    math_tutor = Agent.new(
      provider: :openai,
      model: "gpt-4o-mini",
      messages: [
        Message.system("You are a patient math tutor. Explain concepts step by step.")
      ]
    )
    
    # Create main agent
    agent = Agent.new(
      provider: :openai,
      model: "gpt-4o-mini",
      messages: [Message.system("You coordinate educational tasks.")],
      sub_agents: %{"math_tutor" => math_tutor}
    )
    
    # Demonstrate direct tool usage (this would normally be done by the LLM)
    tool_params = %{
      "sub_agent_name" => "math_tutor",
      "task" => "Explain how to solve quadratic equations",
      "context_data" => %{"student_level" => "high_school"},
      "context" => %{sub_agents: agent.sub_agents}
    }
    
    case Dantex.Tool.SubAgentTool.call(tool_params) do
      {:ok, result} ->
        IO.puts("Delegation successful!")
        IO.puts("Sub-agent used: #{result.sub_agent_used}")
        IO.puts("Response: #{result.response}")
      {:error, reason} ->
        IO.puts("Delegation failed: #{reason}")
    end
  end
end