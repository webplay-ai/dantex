defmodule Dantex.Tool do
  @moduledoc """
  Defines the base behaviour for Dantex tools.
  """

  @type t :: module()

  @doc """
  Executes the tool with the given parameters.
  """
  @callback call(params :: map()) :: {:ok, any()} | {:error, any()}

  @doc """
  Returns the tool's name.
  """
  @callback tool_name() :: String.t()

  @doc """
  Returns the tool's description.
  """
  @callback tool_description() :: String.t()

  @doc """
  Returns the tool's output type.
  """
  @callback tool_output_type() :: atom()

  defmodule Basic do
    @moduledoc """
    A module for creating basic tools that don't need context.

    ## Example

        defmodule DiceTool do
          use Dantex.Tool.Basic

          @tool_name "roll_die"
          @tool_description "Roll a six-sided die and return the result"
          @tool_output_type :string

          def call(_params) do
            {:ok, Integer.to_string(Enum.random(1..6))}
          end
        end
    """

    defmacro __using__(_opts) do
      quote do
        @behaviour Dantex.Tool

        Module.register_attribute(__MODULE__, :tool_name, persist: true)
        Module.register_attribute(__MODULE__, :tool_description, persist: true)
        Module.register_attribute(__MODULE__, :tool_output_type, persist: true)

        @impl true
        def tool_name, do: @tool_name

        @impl true
        def tool_description, do: @tool_description

        @impl true
        def tool_output_type, do: @tool_output_type

        defoverridable tool_name: 0, tool_description: 0, tool_output_type: 0
      end
    end
  end

  defmodule WithContext do
    @moduledoc """
    A module for creating context-aware tools that need access to the agent's context.

    ## Example

        defmodule PlayerNameTool do
          use Dantex.Tool.WithContext

          @tool_name "get_player_name"
          @tool_description "Get the player's name from context"
          @tool_output_type :string

          def call(%{context: ctx}) do
            {:ok, ctx.deps}
          end
        end
    """

    defmacro __using__(_opts) do
      quote do
        @behaviour Dantex.Tool

        Module.register_attribute(__MODULE__, :tool_name, persist: true)
        Module.register_attribute(__MODULE__, :tool_description, persist: true)
        Module.register_attribute(__MODULE__, :tool_output_type, persist: true)

        @impl true
        def tool_name, do: @tool_name

        @impl true
        def tool_description, do: @tool_description

        @impl true
        def tool_output_type, do: @tool_output_type

        defoverridable tool_name: 0, tool_description: 0, tool_output_type: 0
      end
    end
  end
end
