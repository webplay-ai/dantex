# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dantex is an Elixir-based AI agentic framework for building generative AI applications, heavily inspired by Pydantic AI, DeepEval, and Instructor. The main goal is to make it easy to create flexible AI agents with tool calling support and run evaluations on different LLM models.

## Core Architecture

### Agent System (`lib/agent.ex`)
- Agents are containers that group models, messages, and tooling
- Automatic conversation looping - `Agent.run/2` continues until LLM provides final response (no tool calls)
- Support for tool calling with retry limits and tool history tracking
- Provider abstraction with support for OpenAI, Gemini, and Ollama
- Tool adapters for different provider formats (OpenAI format vs XML format) - this is legacy now, we will focus on OpenAI function calling spec
- Built-in safeguard against infinite loops (50 iteration limit) 

### Tool System (`lib/tool.ex`)
- Modern DSL-based tool definitions with inline or external Ecto schema support
- Automatic input/output validation using Ecto schemas
- JSON Schema generation for OpenAI/Ollama function calling
- Tool adapters handle provider-specific formatting (OpenAI vs XML)

### Evaluation Framework (`lib/eval.ex`)
- Systematic evaluation of AI models across different providers
- HTML result generation with DataTables integration
- Support for custom metrics (currently `RegexMatchMetric`)
- Test case management with expected vs actual output comparison

### Provider System (`lib/providers/`)
- Unified interface across OpenAI, Gemini, Anthropic, and Ollama
- Model configuration and chat completion handling
- Provider-specific authentication and API handling

## Common Development Tasks

### Running Tests
```bash
mix test
```

### Type Checking and Linting
```bash
mix dialyzer
mix credo
```

### Generating Evaluations
```bash
# Create new evaluation scaffolding
mix evals.gen my_evaluation_name

# Run evaluation with default model
mix evals.run my_evaluation_name

# Run evaluation with specific provider/model
mix evals.run my_evaluation_name --provider openai --model gpt-4o-mini
```

### Setting Up Evaluations
```bash
# Initialize evaluation cache (run once)
mix evals.setup
```

## Dependencies and Configuration

### Key Dependencies
- `ecto_sql` - Schema validation for tools
- `httpoison` - HTTP client for API calls
- `goth` - Google authentication for Gemini
- `openai_ex` - OpenAI API client
- `dialyxir` - Static analysis
- `credo` - Code quality

### Provider Configuration
Configure providers in `config/config.exs`:
```elixir
config :dantex, :providers,
  openai: %{api_key: System.get_env("OPENAI_API_KEY")},
  gemini: %{api_key: System.get_env("GEMINI_API_KEY")},
  anthropic: %{api_key: System.get_env("ANTHROPIC_API_KEY")},
  ollama: %{api_base: System.get_env("OLLAMA_API_BASE")}
```

## File Structure

- `lib/agent.ex` - Main agent implementation
- `lib/tool.ex` - Tool behavior and adapters
- `lib/eval.ex` - Evaluation framework
- `lib/providers/` - Provider implementations
- `lib/tool/` - Tool adapters and utilities
- `lib/mix/tasks/evals/` - Mix tasks for evaluation management
- `evals/` - Evaluation definitions and results
- `test/` - Test suite

## Supported Models

The framework supports multiple providers and models. See README.md for the complete list of supported models across Ollama, Gemini, Anthropic, and OpenAI providers.
