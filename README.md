# Dantex

Dantex is modern Elixir based AI agentic framework designed to build generative AI apps in Elixir. Dantex is heavily inspired by Pydantic AI, DeepEval and Instructor (and yes also Intructor_ex). 

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

