defmodule Dantex.Tool do
  @moduledoc """
  Defines the base behaviour for Dantex tools.
  """

  alias Dantex.JSONSchema
  require Logger

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
  Validates input parameters against the tool's input schema.
  """
  def validate_input(tool, params) do
    case get_input_schema(tool) do
      nil -> {:ok, params}
      schema -> validate_with_schema(schema, params)
    end
  end

  @doc """
  Validates output result against the tool's output schema.
  """
  def validate_output(tool, result) do
    case get_output_schema(tool) do
      nil -> {:ok, result}
      schema -> validate_with_schema(schema, result)
    end
  end

  @doc """
  Generates JSON Schema for a tool's input schema.
  """
  def generate_input_json_schema(tool) do
    case get_input_schema(tool) do
      nil -> Jason.encode!(%{type: "object", properties: %{}})
      schema -> JSONSchema.from_ecto_schema(schema)
    end
  end

  @doc """
  Generates JSON Schema for a tool's output schema.
  """
  def generate_output_json_schema(tool) do
    case get_output_schema(tool) do
      nil ->
        Jason.encode!(%{type: "object", properties: %{}})
      schema ->
        schema |> JSONSchema.from_ecto_schema()
    end
  end

  @doc """
  Generates a complete JSON Schema for the tool to be used with OpenAI or Ollama function calling.
  """
  def generate_tool_json_schema(tool) do
    # Get the tool name and description from the module
    name = tool.tool_name()
    description = tool.tool_description()

    input_schema = get_input_schema(tool)

    # Get the input schema properties
    input_properties =
      if input_schema do
        # Generate the JSON schema string and then decode it back to a map
        input_schema
        |> JSONSchema.from_ecto_schema()
        |> Jason.decode!()
        |> Map.get("properties", %{})
      else
        %{}
      end

    # Get the required fields (fields without default values)
    required_fields =
      if input_schema do
        # For simplicity, let's consider all fields as required
        # In a real implementation, you would need to check which fields have default values
        # and exclude them from the required list
        input_schema.__schema__(:fields)
        |> Enum.map(&Atom.to_string/1)
      else
        []
      end

    # Build the complete tool schema
    %{
      "name" => name,
      "description" => description,
      "parameters" => %{
        "type" => "object",
        "properties" => input_properties,
        "required" => required_fields
      }
    }
    |> Jason.encode!()
  end

  @doc """
  Parses a JSON string using a tool's input schema.
  """
  def parse_input_json(tool, json_string) do
    with {:ok, data} <- Jason.decode(json_string),
         {:ok, validated} <- validate_input(tool, data) do
      {:ok, validated}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parses a JSON string using a tool's output schema.
  """
  def parse_output_json(tool, json_string) do
    with {:ok, data} <- Jason.decode(json_string),
         {:ok, validated} <- validate_output(tool, data) do
      {:ok, validated}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Helper functions

  @doc """
  Gets the input schema for a tool.
  """
  def get_input_schema(tool) do
    if function_exported?(tool, :__input_schema__, 0) do
      tool.__input_schema__()
    else
      nil
    end
  end

  @doc """
  Gets the output schema for a tool.
  """
  def get_output_schema(tool) do
    result = if function_exported?(tool, :__output_schema__, 0) do
      tool.__output_schema__()
    else
      nil
    end
    result
  end

  @doc """
  Validates a map against an Ecto schema.
  """
  defp validate_with_schema(schema, data) do
    # Create a struct from the schema
    struct = struct(schema)

    # Get the changeset function
    changeset_fn = &schema.changeset/2

    # Create a changeset from the data
    changeset = changeset_fn.(struct, data)

    case changeset do
      %Ecto.Changeset{valid?: true} ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}

      %Ecto.Changeset{valid?: false} ->
        {:error, changeset.errors}
    end
  end

  defmodule Basic do
    @moduledoc """
    A module for creating basic tools that don't need context.

    ## Example

        defmodule DiceTool do
          use Dantex.Tool.Basic

          @tool_name "roll_die"
          @tool_description "Roll a six-sided die and return the result"

          def do_call(_params) do
            {:ok, Integer.to_string(Enum.random(1..6))}
          end
        end
    """

    defmacro __using__(_opts) do
      quote do
        @behaviour Dantex.Tool

        # Register module attributes with persist: true
        Module.register_attribute(__MODULE__, :tool_name, persist: true)
        Module.register_attribute(__MODULE__, :tool_description, persist: true)
        Module.register_attribute(__MODULE__, :input_schema, persist: true)
        Module.register_attribute(__MODULE__, :output_schema, persist: true)

        # Import necessary modules
        import Ecto.Changeset, only: [validate_required: 2, validate_inclusion: 3, validate_number: 3]
        import Dantex.Tool.SchemaHelpers

        # Register a before_compile hook to inject functions that depend on module attributes
        @before_compile Dantex.Tool.Basic

        # This is what tool implementers will override
        def do_call(_params), do: {:error, :not_implemented}

        defoverridable do_call: 1
      end
    end

    # This callback is invoked at compile time after all attributes have been defined
    defmacro __before_compile__(_env) do
      quote do
        @impl true
        def tool_name, do: @tool_name

        @impl true
        def tool_description, do: @tool_description

        # Define functions to access the schemas
        def __input_schema__ do
          @input_schema
        end

        def __output_schema__ do
          @output_schema
        end

        # Override the call function to automatically handle validation
        def call(params) do
          with {:ok, validated_params} <- Dantex.Tool.validate_input(__MODULE__, params),
               {:ok, result} <- do_call(validated_params),
               {:ok, validated_result} <- Dantex.Tool.validate_output(__MODULE__, result) do
            {:ok, validated_result}
          end
        end
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

          def do_call(%{context: ctx}) do
            {:ok, ctx.deps}
          end
        end
    """

    defmacro __using__(_opts) do
      quote do
        @behaviour Dantex.Tool

        # Register module attributes with persist: true
        Module.register_attribute(__MODULE__, :tool_name, persist: true)
        Module.register_attribute(__MODULE__, :tool_description, persist: true)
        Module.register_attribute(__MODULE__, :input_schema, persist: true)
        Module.register_attribute(__MODULE__, :output_schema, persist: true)

        # Import necessary modules
        import Ecto.Changeset, only: [validate_required: 2, validate_inclusion: 3, validate_number: 3]
        import Dantex.Tool.SchemaHelpers

        # Register a before_compile hook to inject functions that depend on module attributes
        @before_compile Dantex.Tool.WithContext

        # This is what tool implementers will override
        def do_call(_params), do: {:error, :not_implemented}

        defoverridable do_call: 1
      end
    end

    # This callback is invoked at compile time after all attributes have been defined
    defmacro __before_compile__(_env) do
      quote do
        @impl true
        def tool_name, do: @tool_name

        @impl true
        def tool_description, do: @tool_description

        # Define functions to access the schemas
        def __input_schema__ do
          @input_schema
        end

        def __output_schema__ do
          @output_schema
        end

        # Override the call function to automatically handle validation
        def call(params) do
          with {:ok, validated_params} <- Dantex.Tool.validate_input(__MODULE__, params),
               {:ok, result} <- do_call(validated_params),
               {:ok, validated_result} <- Dantex.Tool.validate_output(__MODULE__, result) do
            {:ok, validated_result}
          end
        end
      end
    end
  end
end
