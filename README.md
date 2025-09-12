# Dantex

Dantex is modern Elixir based AI agentic framework designed to build generative AI apps in Elixir. Dantex is heavily inspired by Pydantic AI, DeepEval and Instructor (and yes also Intructor_ex). 

The main goal of Dantex is to make it very easy to run a lot of evals on different LLM models. 

## Why Dantex?
First of all, thanks for all the great work done by Instructor_ex (and Instructor) and Pydantic AI. Dantex is heavily inspired upon these libraries/frameworks. If you only want to use structured responses from LLM's, by all means, just use Instructor_ex. It is much more mature then Dantex.

At this point I believe Instructor_ex is the best framework in the Elixir ecosystem to build generative AI apps. However, Instructor_ex is very opinionated, which more or less forces you to use Ecto Schema's - even if you sometimes don't need it. Dantex is an unopoinoated and flexible answer to this. It provides you all the building blocks you need to build AI Agents in Elixir by the standards of 2025. We try to make as little assumptions about your use case as possible, while trying not to bloat the API interface to much. 

## Installation

```elixir
def deps do
  [
    {:dantex, "~> 0.1.0"}
  ]
end
```

## Features

- Support for Anthropic, Ollama, OpenAI and Gemini
- Tool calling with modern DSL syntax
- Flexible tool definitions using Ecto schemas or inline parameter specifications
- Automatic input validation and JSON Schema generation for function calling
- Context support for sharing data between tools and agents
- Eval scaffolding using `mix evals.gen some_name_for_your_eval`
- Run evals using on the same data set, using different models `mix evals.run some_name_for_your_eval --provider ollama --model gemma3:4b`

## Configuration

To configure the providers, add the following to your `config/config.exs` or `config/runtime.exs` file:

```elixir
config :dantex, :providers,
  openai: %{
    api_key: System.get_env("OPENAI_API_KEY")
  },
  gemini: %{
    api_key: System.get_env("GEMINI_API_KEY")
  },
  anthropic: %{
    api_key: System.get_env("ANTHROPIC_API_KEY")
  },
  ollama: %{
    api_base: System.get_env("OLLAMA_API_BASE")
  }
```

## Usage

Dantex provides a modern DSL for defining tools with automatic validation and context support.

```elixir
alias Dantex.{Agent, Message}

agent = Agent.new(
  provider: :openai,
  model: "gpt-4o-mini",
  messages: [Message.system("You are a helpful assistant.")],
  tools: [MyCalculatorTool, SimpleWeatherTool],
  context: %{
    precision: 3,
  }
)

{:ok, response, updated_agent} = Agent.run(agent, "Calculate 15.5 + 23.2 and get weather for Tokyo")
```

You can define tools using Ecto schema's: 

```elixir
defmodule CalculatorInputSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :operation, :string
    field :a, :float
    field :b, :float
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:operation, :a, :b])
    |> validate_required([:operation, :a, :b])
    |> validate_inclusion(:operation, ["add", "subtract", "multiply", "divide"])
  end
end

defmodule MyCalculatorTool do
  use Dantex.Tool

  tool :calculate,
    description: "Perform mathematical operations",
    input: CalculatorInputSchema do

    # Access context if needed
    precision = Map.get(context, :precision, 2)
    
    # Perform calculation
    result = case params.operation do
      "add" -> params.a + params.b
      "subtract" -> params.a - params.b
      "multiply" -> params.a * params.b
      "divide" -> params.a / params.b
    end

    %{
      result: Float.round(result, precision),
      operation: params.operation,
      expression: "#{params.a} #{get_operator(params.operation)} #{params.b}"
    }
  end

  defp get_operator("add"), do: "+"
  defp get_operator("subtract"), do: "-"
  defp get_operator("multiply"), do: "*"
  defp get_operator("divide"), do: "/"
end
```

Adn you can define tools with inline input parameters: 

```elixir
defmodule SimpleWeatherTool do
  use Dantex.Tool

  tool :get_weather,
    description: "Get weather information",
    input: [
      location: [:string, required: true, min_length: 1],
      units: [:string, default: "celsius", enum: ["celsius", "fahrenheit"]],
      days: [:integer, default: 1, min: 1, max: 7]
    ] do

    # Access context for API keys
    api_key = context[:weather_api_key] || "demo_key"
    
    # Mock weather data
    forecast = for day <- 1..params.days do
      %{
        day: day,
        temp: 20.0 + (day * 0.5),
        conditions: Enum.at(["Sunny", "Cloudy", "Rainy"], rem(day - 1, 3))
      }
    end
    
    %{
      location: params.location,
      units: params.units,
      forecast: forecast
    }
  end
end
```


