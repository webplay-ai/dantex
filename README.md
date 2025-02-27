# Dantex

Dantex is heavily inspired by both multiple Python based AI frameworks, like Pydantic AI, Instructor (and yes also Intructor_ex) and DeepEval. 

## Motivation
First of all, thanks for all the great work done by Instructor_ex (and Instructor) and Pydantic AI. Dantex is heavily inspired upon these libraries/frameworks. If you only want to use structured responses from LLM's, by all means, just use Instructor_ex. It is much more mature then Dantex. 

## Why Dantex?
A while ago I've decided to build AI Agentic workflows solely in Elixir. 

Instructor_ex is a very opinionated library which more or less forces you to use Schema. It is unopoinoated. It provides you all the building blocks to build AI Agents in Elixir by the standards of 2025. It is unopionated and flexible. We try to make as little assumptions about your use case as possible, while trying not to bloat the API interface to much. 


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

