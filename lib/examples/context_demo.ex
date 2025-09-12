defmodule Dantex.Examples.ContextDemo do
  @moduledoc """
  Demonstration of the new DSL tool system with context support.
  
  This example shows:
  1. How to create tools using the new DSL syntax
  2. How to access context within tool execution
  3. How to create agents with context
  """
  
  alias Dantex.{Agent, Message}
  
  def demo do
    # Create agent with context containing API keys and user info
    agent = Agent.new(
      provider: :openai,
      model: "gpt-4o-mini", 
      messages: [Message.system("You are a helpful assistant with access to stock and weather tools.")],
      tools: [Dantex.Examples.StockTool, Dantex.Examples.WeatherTool, Dantex.Examples.CalculatorTool, Dantex.Examples.SimpleWeatherTool],
      context: %{
        api_key: "demo_api_key_123",
        weather_api_key: "weather_demo_key", 
        user_id: 456,
        precision: 2
      }
    )
    
    # Test the tools with context
    IO.puts("=== Testing New DSL Tool System with Context ===")
    IO.puts("\n1. Stock Tool:")
    IO.inspect(Dantex.Examples.StockTool.tool_name())
    IO.inspect(Dantex.Examples.StockTool.tool_description())
    
    IO.puts("\n2. Weather Tool:")
    IO.inspect(Dantex.Examples.WeatherTool.tool_name())
    IO.inspect(Dantex.Examples.WeatherTool.tool_description())
    
    IO.puts("\n3. Calculator Tool:")
    IO.inspect(Dantex.Examples.CalculatorTool.tool_name())
    IO.inspect(Dantex.Examples.CalculatorTool.tool_description())
    
    IO.puts("\n4. Simple Weather Tool (using inline parameters):")
    IO.inspect(Dantex.Examples.SimpleWeatherTool.tool_name())
    IO.inspect(Dantex.Examples.SimpleWeatherTool.tool_description())
    
    # Test direct tool calls with context
    IO.puts("\n=== Direct Tool Calls ===")
    
    # Test calculator tool
    calc_params = %{
      operation: "multiply",
      a: 10.5,
      b: 2.0,
      context: %{precision: 3}
    }
    
    IO.puts("\nCalculator Tool Test:")
    case Dantex.Examples.CalculatorTool.call(calc_params) do
      {:ok, result} -> IO.inspect(result, label: "Calculator Result")
      {:error, error} -> IO.inspect(error, label: "Calculator Error")
    end
    
    # Test weather tool
    weather_params = %{
      location: "San Francisco",
      days: 3,
      context: %{weather_api_key: "demo_key_123"}
    }
    
    IO.puts("\nWeather Tool Test:")
    case Dantex.Examples.WeatherTool.call(weather_params) do
      {:ok, result} -> IO.inspect(result, label: "Weather Result")
      {:error, error} -> IO.inspect(error, label: "Weather Error")
    end
    
    # Test simple weather tool with inline parameters
    simple_weather_params = %{
      location: "New York",
      units: "fahrenheit",
      days: 2,
      context: %{weather_api_key: "simple_demo_key"}
    }
    
    IO.puts("\nSimple Weather Tool Test:")
    case Dantex.Examples.SimpleWeatherTool.call(simple_weather_params) do
      {:ok, result} -> IO.inspect(result, label: "Simple Weather Result")
      {:error, error} -> IO.inspect(error, label: "Simple Weather Error")
    end
    
    {:ok, agent}
  end
end