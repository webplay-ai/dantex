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
- Tool calling
- Define tool calls using XML using the Dantex.Tool.XMLAdapter
- Ecto schema validations for tool call input parameters and tool outputs 
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

## Todo

- [ ] return actual tokens used in message? we need to add this to eval.run
- [ ] add extensive docs
- [ ] add more docs/examples and test for ecto based schema validations