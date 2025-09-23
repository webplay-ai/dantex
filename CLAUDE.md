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
- **Remote tool support** for provider-native tools (like Anthropic's web search)
- MCP (Model Context Protocol) support for external tool servers via Hermes package

### Evaluation Framework (`lib/eval.ex`)
- Systematic evaluation of AI models across different providers
- HTML result generation with DataTables integration
- Support for custom metrics (currently `RegexMatchMetric`)
- Test case management with expected vs actual output comparison

### Provider System (`lib/providers/`)
- Unified interface across OpenAI, Gemini, Anthropic, Ollama, Baseten, and Together AI
- Model configuration and chat completion handling
- Provider-specific authentication and API handling

### Tool Adapters (`lib/tool/`)

Tool adapters allow you to parse custom tool call formats from different models. By default, agents use the OpenAI function calling format, but some models (like Kimi K2) use custom formats that require special parsing.

#### Using Kimi K2 Tool Adapter for Together AI

For models that output tool calls in Kimi K2 format (e.g., `meta-llama/Llama-3.2-11B-Vision-Instruct-Turbo`), use the `KimiK2Adapter`:

```elixir
agent = Agent.new(
  provider: :together,
  model: "meta-llama/Llama-3.2-11B-Vision-Instruct-Turbo",
  messages: [Message.system("You are a helpful assistant.")],
  tools: [MyCustomTool],
  tool_adapter: Dantex.Tool.KimiK2Adapter  # Parse Kimi K2 tool call format
)
```

The Kimi K2 adapter parses the special format:
```
<|tool_calls_section_begin|>
<|tool_call_begin|>functions.function_name:0<|tool_call_argument_begin|>{"arg": "value"}<|tool_call_end|>
<|tool_calls_section_end|>
```

#### Available Tool Adapters

- `Dantex.Tool.OpenAIAdapter` (default) - Standard OpenAI function calling format
- `Dantex.Tool.KimiK2Adapter` - Kimi K2 custom tool call format for Together AI models

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
- `hermes_mcp` - MCP (Model Context Protocol) client support
- `dialyxir` - Static analysis
- `credo` - Code quality

### Provider Configuration
Configure providers in `config/config.exs`:
```elixir
config :dantex, :providers,
  openai: %{api_key: System.get_env("OPENAI_API_KEY")},
  gemini: %{api_key: System.get_env("GEMINI_API_KEY")},
  anthropic: %{api_key: System.get_env("ANTHROPIC_API_KEY")},
  ollama: %{api_base: System.get_env("OLLAMA_API_BASE")},
  baseten: %{
    api_key: System.get_env("BASETEN_API_KEY"),
    # Optional: customize model parameters
    temperature: 1.0,
    max_tokens: 8000,
    top_p: 1.0,
    presence_penalty: 0,
    frequency_penalty: 0,
    stop: []
  },
  together: %{
    api_key: System.get_env("TOGETHER_API_KEY"),
    # Optional: customize model parameters
    temperature: 0.7,
    max_tokens: 512,
    top_p: 0.7,
    stop: [],
    # Together AI specific options
    safety_model: nil,  # Optional safety model for content moderation
    stream: false       # Enable streaming responses
  }

# Optional: Configure MCP tool filtering
config :dantex, :mcp_filters,
  MyApp.MCP.FileSystemClient: %{
    allow: ["read_file", "list_directory"],
    block: ["delete_file", "format_disk"]
  }
```

## File Structure

- `lib/agent.ex` - Main agent implementation
- `lib/tool.ex` - Tool behavior and adapters
- `lib/eval.ex` - Evaluation framework
- `lib/providers/` - Provider implementations
- `lib/tool/` - Tool adapters and utilities
- `lib/tool/mcp/` - MCP tool wrappers and utilities
- `lib/examples/mcp/` - Example MCP client implementations
- `lib/mix/tasks/evals/` - Mix tasks for evaluation management
- `evals/` - Evaluation definitions and results
- `test/` - Test suite

## MCP (Model Context Protocol) Support

### Overview
Dantex includes first-class support for MCP, allowing agents to use tools from external MCP servers alongside local tools. MCP tools are automatically discovered, validated, and integrated into the agent's tool set.

### Setting Up MCP Clients
```elixir
# 1. Create MCP client modules
defmodule MyApp.MCP.FileSystemClient do
  use Hermes.Client,
    name: "FileSystemClient",
    version: "1.0.0",
    protocol_version: "2024-11-05",
    capabilities: []
end

# 2. Add to supervision tree
children = [
  {MyApp.MCP.FileSystemClient,
   transport: {:stdio, command: "npx", args: ["@modelcontextprotocol/server-filesystem", "/workspace"]}}
]

# 3. Use in agents
agent = Agent.new(
  provider: :openai,
  model: "gpt-4o-mini",
  tools: [MyLocalTool],
  mcp_clients: [MyApp.MCP.FileSystemClient],
  mcp_filters: %{
    MyApp.MCP.FileSystemClient => %{
      allow: ["read_file", "list_directory"],
      block: ["delete_file", "write_file"]
    }
  }
)
```

### MCP Tool Filtering
- **Whitelist/Blacklist**: `allow: [tools]`, `block: [tools]`
- **Pattern Filtering**: `allow_patterns: [regexes]`, `block_patterns: [regexes]`
- **Security Levels**: `security_level: :safe | :moderate | :dangerous`
- **Configuration-based**: Set defaults in `config/config.exs`

### Available MCP Servers
- `@modelcontextprotocol/server-filesystem` - File operations
- `@modelcontextprotocol/server-brave-search` - Web search
- `@modelcontextprotocol/server-github` - GitHub operations
- `@modelcontextprotocol/server-postgres` - Database operations
- And many more from the MCP ecosystem

## Supported Models

The framework supports multiple providers and models. See README.md for the complete list of supported models across Ollama, Gemini, Anthropic, and OpenAI providers.
