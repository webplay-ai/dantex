defmodule Dantex.Tool.SubAgentTool do
  @moduledoc """
  Tool that allows an agent to delegate tasks to its sub-agents.
  
  This tool enables hierarchical agent composition where a parent agent
  can delegate specific tasks to specialized sub-agents.
  """
  
  use Dantex.Tool
  
  tool :delegate_to_sub_agent,
    description: "Delegate a task to a specialized sub-agent. Use this when you encounter a task that would benefit from specialized expertise like code review, debugging, data analysis, etc.",
    input: [
      sub_agent_name: [:string, required: true, doc: "Name of the sub-agent to delegate to"],
      task: [:string, required: true, min_length: 1, doc: "The task description to send to the sub-agent"],
      context_data: [:map, default: %{}, doc: "Additional context data to pass to the sub-agent"]
    ] do
    
    # Extract sub-agents from the context
    sub_agents = context[:sub_agents] || %{}
    
    case Map.get(sub_agents, params.sub_agent_name) do
      nil ->
        available_agents = Map.keys(sub_agents) |> Enum.join(", ")
        {:error, "Sub-agent '#{params.sub_agent_name}' not found. Available sub-agents: #{available_agents}"}
      
      sub_agent ->
        # Merge the context data with the sub-agent's existing context
        enhanced_context = Map.merge(sub_agent.context, params.context_data)
        updated_sub_agent = %{sub_agent | context: enhanced_context}
        
        # Delegate the task to the sub-agent
        case Dantex.Agent.run(updated_sub_agent, params.task) do
          {:ok, response, _updated_sub_agent} ->
            {:ok, %{
              response: response.content,
              sub_agent_used: params.sub_agent_name,
              task: params.task
            }}
          
          {:error, reason} ->
            {:error, "Sub-agent execution failed: #{inspect(reason)}"}
        end
    end
  end
end