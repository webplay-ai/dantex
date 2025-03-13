defmodule Dantex.Agent do
  @moduledoc """
  Agents are containers that group model, system prompt, tooling and response formats.

  Future considerations:
  - How about if agents could decide to use different LLMs and switch from model in function tool calling theirselves? We just have to move the model to the run function instead. That would mean an agent is nothing more then a bunch of messages. You can have replace the system prompt.

  ## Example

      alias Dante.{Agent, Model, Prompt, Response, ResponseFormat, Message}

      model = Model.new("gpt-4")

      # or a mock model so we can unit or end 2 end test our business logic
      mock = Model.mock([%{ role: system, content: "foo"}])
      mock.pushMessages([%{ role: user, content: "another message"}])

      # optionally we can define the response format schemas. Response format is best used in case you want structured outputs from the LLM
      response_format = ResponseFormat.new(
        type: :ecto_schema, :json_schema
        format: EctoSchema | JSON schema definition,
        schema: %Ecto.Schema{
          fields: %{
            text: :string
          }
        }
      )

      response = Response.new(format: response_format)

      # Define a plain tool
      defmodule DiceTool do
        use Dantex.Tool.Plain

        @tool_name "roll_die"
        @tool_description "Roll a six-sided die and return the result"

        def call(_params) do
          {:ok, Integer.to_string(Enum.random(1..6))}
        end
      end

      # If you want to append the @doctool tag documentations to the system prompt, you can use
      system_prompt = Prompt.system("Roll the die")
      |> Prompt.add_tools([DiceTool, PlayerTool])

      # Create an agent
      agent = Agent.new(
        model: model,
        tools: [DiceTool], // optional
        response_format: response_format | EctoSchema | JSON Schema definition (optional)
        logger: Logger,
        telementry: true
      )

      # Run the agent
      {:ok, raw_response } = Agent.run(agent, "Roll the die")
  """

  alias Dantex.{Tool, Model, Tool, Message, Provider}

  @type t :: %__MODULE__{
          model: Model.t(),
          tools: [Tool.t()],
          messages: [Message.t()]
          # response_format: ResponseFormat.t() | nil,
          # logger: module() | nil
        }

  defstruct [
    :model,
    :tools,
    :messages
    # :response_format,
    # :logger
  ]

  @doc """
  Creates a new agent with the given configuration.

  ## Options

    * `:provider` - The AI model provider to use (required)
    * `:model` - The AI model to use (required)
    * `:system_prompt` - The system prompt for the agent (required)
    * `:messages` - A list of prompt messages (required)
    * `:tools` - List of tool modules to use (default: [])
    * `:response_format` - Optional module for response validation

  ## Example

      Agent.new(
        provider: :openai,
        model: "gpt-4o",
        messages: ["You are a helpful assistant"],
        tools: [WeatherTool, TimeTool],
      )
  """
  require Logger

  @spec new([
          {:provider, atom()}
          | {:model, String.t()}
          | {:messages, [Message.t()]}
          | {:tools, [Tool.t()]}
        ]) ::
          t()
  def new(opts) do
    provider = Keyword.get(opts, :provider, :openai)
    model = Keyword.get(opts, :model, "gpt-4o-mini")
    tools = Keyword.get(opts, :tools, [])
    messages = Keyword.get(opts, :messages, [])

    # system_prompt = build_system_prompt(system_prompt, tools)

    %__MODULE__{
      model: Model.new(provider, model),
      messages: messages,
      # system_prompt: system_prompt,
      tools: tools
      # response_format: response_format,
      # logger: logger
    }
  end

  @doc """
  Adds additional tools to an existing agent.

  ## Example

      agent = Agent.new(model: "gpt-4", system_prompt: "...")
      agent = Agent.add_tools(agent, [WeatherTool, TimeTool])
  """
  @spec add_tools(t(), [Tool.t()]) :: t()
  def add_tools(%__MODULE__{} = agent, tools) when is_list(tools) do
    %{agent | tools: agent.tools ++ tools}
  end

  @doc """
  Runs the agent with the given prompt.

  ## Example

      {:ok, response} = Agent.run(agent, "What's the weather?")
  """
  @spec run(t(), Message.t() | String.t()) ::
          {:ok, {Message.t(), [Message.t()], t()}, Provider.usage()} | {:error, term()}
  def run(%__MODULE__{} = agent, user_prompt) do
    with {:ok, messages} <- build_messages(agent, user_prompt),
         {:ok, {last_msg, all_msgs}, usage} <- chat_completion(agent, messages) do
      updated_agent = %{agent | messages: messages ++ [last_msg]}
      {:ok, {last_msg, all_msgs, updated_agent}, usage}
    end
  end

  @spec build_messages(t(), Message.t() | String.t()) :: {:ok, list(Message.t())}
  defp build_messages(%__MODULE__{messages: messages} = agent, %Message{} = user_prompt) do
    {:ok, messages ++ [user_prompt]}
  end

  defp build_messages(%__MODULE__{messages: messages} = agent, user_prompt)
       when is_binary(user_prompt) do
    {:ok, messages ++ [Message.user(user_prompt)]}
  end

  @spec chat_completion(t(), list(Message.t())) ::
          {:ok, {Message.t(), [Message.t()]}, Provider.usage()} | {:error, term()}
  defp(chat_completion(agent, messages)) do
    Model.chat_completion(agent.model, messages, agent.tools)
  end
end
