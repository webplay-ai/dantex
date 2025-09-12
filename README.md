# Dantex

Dantex is modern Elixir based AI agentic framework designed to build generative AI apps in Elixir. Dantex is heavily inspired by Pydantic AI, DeepEval and Instructor (and yes also Intructor_ex). 

The main goal of Dantex is to make it very easy to run a lot of evals on different LLM models. 

## Why Dantex?
First of all, thanks for all the great work done by Instructor_ex (and Instructor) and Pydantic AI. Dantex is heavily inspired upon these libraries/frameworks. If you only want to use structured responses from LLM's, by all means, just use Instructor_ex. It is much more mature then Dantex.

At this point I believe Instructor_ex is the best framework in the Elixir ecosystem to build generative AI apps. However, Instructor_ex is very opinionated, which more or less forces you to use Ecto Schema's - even if you sometimes don't need it. Dantex is an unopoinoated and flexible answer to this. It provides you all the building blocks you need to build AI Agents in Elixir by the standards of 2025. We try to make as little assumptions about your use case as possible, while trying not to bloat the API interface to much. 

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dantex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dantex, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/dantex>.

## Features

- Support for Ollama, OpenAI and Gemini
- Tool calling with modern DSL syntax
- Flexible tool definitions using Ecto schemas or inline parameter specifications
- Automatic input/output validation and JSON Schema generation for OpenAI function calling
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
  ollama: %{
    api_base: System.get_env("OLLAMA_API_BASE")
  }
```

## Supported Models

| Provider | Model |
|---|---|
| Ollama | gemma3:4b |
| Ollama | gemma3:1b |
| Ollama | gemma3:7b |
| Ollama | gemma3:12b |
| Ollama | deepseek-r1:1.5b |
| Ollama | deepseek-r1:7b |
| Ollama | deepseek-r1:8b |
| Ollama | deepseek-r1:14b |
| Ollama | deepseek-r1:32b |
| Ollama | llama3.2 |
| Ollama | llama3.2:1b |
| Gemini | gemini-2.0-flash |
| Gemini | gemini-2.0-flash-lite |
| Gemini | gemini-1.5-flash |
| Gemini | gemini-1.5-flash-8b |
| Gemini | gemini-1.5-pro |
| OpenAI | gpt-4o-2024-08-06 |
| OpenAI | gpt-4o-mini-2024-07-18 |
| OpenAI | gpt-3.5-turbo-0125 |
| OpenAI | o3-mini-2025-01-31 |
| OpenAI | o1-mini-2024-09-12 |
| OpenAI | o1-2024-12-17 |
| OpenAI | gpt-4.5-preview-2025-02-27 |

## Usage

### Creating Tools with the New DSL

Dantex provides a modern DSL for defining tools with automatic validation and context support.

#### Example 1: Tool with External Ecto Schemas

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

defmodule CalculatorOutputSchema do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :result, :float
    field :operation, :string
    field :expression, :string
  end
end

defmodule MyCalculatorTool do
  use Dantex.Tool

  tool :calculate,
    description: "Perform mathematical operations",
    input: CalculatorInputSchema,
    output: CalculatorOutputSchema do

    # Access context if needed
    precision = Map.get(context, :precision, 2)
    
    # Perform calculation
    result = case params.operation do
      "add" -> params.a + params.b
      "subtract" -> params.a - params.b
      "multiply" -> params.a * params.b
      "divide" -> params.a / params.b
    end

    # Return structured output
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

#### Example 2: Tool with Inline Parameter Definitions

```elixir
defmodule SimpleWeatherTool do
  use Dantex.Tool

  tool :get_weather,
    description: "Get weather information",
    input: [
      location: [:string, required: true, min_length: 1],
      units: [:string, default: "celsius", enum: ["celsius", "fahrenheit"]],
      days: [:integer, default: 1, min: 1, max: 7]
    ],
    output: [
      location: :string,
      units: :string,
      forecast: {:array, :map}
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

### Using Tools with Agents

```elixir
alias Dantex.{Agent, Message}

# Create agent with tools and context
agent = Agent.new(
  provider: :openai,
  model: "gpt-4o-mini",
  messages: [Message.system("You are a helpful assistant.")],
  tools: [MyCalculatorTool, SimpleWeatherTool],
  context: %{
    precision: 3,
    weather_api_key: "your_api_key"
  }
)

# Send a message that will trigger tool calls
{:ok, agent} = Agent.run(agent, "Calculate 15.5 + 23.2 and get weather for Tokyo")
```

## Todo

- [ ] extend API with more functions to work with context windows - getMessageByIndex, getResponseByIndex, getAllPrompts, getAllResponses, getAllMessages
- [ ] extend API to template prompts template prompts, renderPrompt
- [ ] extend API to build switch statements based on llm outputs, handleToolCall
- [ ] build in mechanism to kill agent after X number of tokens or X number of messages. default off.
- [ ] return actual tokens used in message? we need to add this to eval.run
- [ ] add extensive docs
- [ ] add more docs/examples and test for ecto based schema validations