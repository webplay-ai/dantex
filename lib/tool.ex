defmodule Dantex.Tool do
  @moduledoc """
  Defines the base behaviour for Dantex tools and provides a DSL for creating tools.

  ## Usage

  ### External Ecto Schemas
      defmodule MyTool do
        use Dantex.Tool

        tool :my_function,
          description: "Does something useful",
          input: MyInputSchema,
          output: MyOutputSchema do

          # Access context if needed
          api_key = context[:api_key]

          # Tool logic here
          %{result: "success"}
        end
      end

  ### Inline Schema Definitions
      defmodule MyTool do
        use Dantex.Tool

        tool :my_function,
          description: "Does something useful",
          input: [
            name: [:string, required: true, min_length: 1],
            age: [:integer, min: 0, max: 150],
            role: [:string, default: "user", enum: ["user", "admin"]]
          ],
          output: [
            message: :string,
            success: :boolean
          ] do

          # Access context and validated params
          api_key = context[:api_key]

          # Tool logic here (params and context available in do block)
          %{
            message: "Hello " <> params.name,
            success: true
          }
        end
      end

  """

  alias Dantex.Tool.Validation
  alias Dantex.Tool.JSONSchema
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
  Defines a tool with the DSL syntax.

  Supports both external Ecto schemas and inline schema definitions:
  """
  defmacro tool(name, opts, do: block) do
    description = Keyword.get(opts, :description, "")
    input_spec = Keyword.get(opts, :input)
    output_spec = Keyword.get(opts, :output)

    # Determine if input/output are inline schemas (lists) or external schemas (modules)
    {input_schema, output_schema} = process_schema_specs(name, input_spec, output_spec)

    quote do
      # Generate dynamic schemas if inline definitions are provided
      unquote(generate_inline_schemas(name, input_spec, output_spec))

      # Store the tool definition
      @tool_definitions {unquote(name), unquote(description), unquote(input_schema),
                         unquote(output_schema), unquote(Macro.escape(block))}

      # Set the attributes for this tool
      @tool_name Atom.to_string(unquote(name))
      @tool_description unquote(description)
      @input_schema unquote(input_schema)
      @output_schema unquote(output_schema)
    end
  end


  @doc """
  Main macro for using the DSL-based tool definition.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Dantex.Tool

      # Register module attributes
      Module.register_attribute(__MODULE__, :tool_definitions, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :tool_name, persist: true)
      Module.register_attribute(__MODULE__, :tool_description, persist: true)
      Module.register_attribute(__MODULE__, :input_schema, persist: true)
      Module.register_attribute(__MODULE__, :output_schema, persist: true)

      # Make the tool macro available in the module
      require unquote(__MODULE__)
      import unquote(__MODULE__), only: [tool: 3]

      # Register a before_compile hook
      @before_compile Dantex.Tool

      # Default implementations (can be overridden by the tool macro)
      def call(_params), do: {:error, :not_implemented}
      def tool_name, do: nil
      def tool_description, do: nil

      defoverridable call: 1, tool_name: 0, tool_description: 0
    end
  end

  # This callback is invoked at compile time after all attributes have been defined
  defmacro __before_compile__(env) do
    tool_definitions = Module.get_attribute(env.module, :tool_definitions)

    if tool_definitions && length(tool_definitions) > 0 do
      {_name, _description, _input_schema, _output_schema, block} = hd(tool_definitions)

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

        # Generate the call function that wraps the tool logic
        @impl true
        def call(params) do
          with {:ok, validated_params} <- Validation.validate_input(__MODULE__, params) do
            try do
              # Execute the tool block with context support
              context = Map.get(params, :context, %{})

              # Make params and context available in the block
              result =
                (fn ->
                   var!(params) = validated_params
                   var!(context) = context
                   unquote(block)
                 end).()

              # Validate the output
              case Validation.validate_output(__MODULE__, result) do
                {:ok, validated_result} -> {:ok, validated_result}
                {:error, _} = error -> error
              end
            rescue
              error -> {:error, Exception.message(error)}
            end
          end
        end
      end
    else
      # No tool definitions, use defaults
      quote do
        def __input_schema__, do: nil
        def __output_schema__, do: nil
      end
    end
  end

  # Process schema specifications to determine if they're inline or external
  defp process_schema_specs(name, input_spec, output_spec) do
    input_schema =
      if is_list(input_spec) do
        create_dynamic_schema_name(name, "Input")
      else
        input_spec
      end

    output_schema =
      if is_list(output_spec) do
        create_dynamic_schema_name(name, "Output")
      else
        output_spec
      end

    {input_schema, output_schema}
  end

  # Generate inline schema modules if needed
  defp generate_inline_schemas(name, input_spec, output_spec) do
    schemas = []

    # Generate input schema if it's an inline definition
    schemas =
      if is_list(input_spec) do
        input_module = create_dynamic_schema_name(name, "Input")
        [create_inline_schema(input_module, input_spec) | schemas]
      else
        schemas
      end

    # Generate output schema if it's an inline definition  
    schemas =
      if is_list(output_spec) do
        output_module = create_dynamic_schema_name(name, "Output")
        [create_inline_schema(output_module, output_spec) | schemas]
      else
        schemas
      end

    {:__block__, [], schemas}
  end

  # Helper function to create dynamic schema module name
  defp create_dynamic_schema_name(tool_name, suffix) do
    module_name =
      tool_name
      |> Atom.to_string()
      |> Macro.camelize()

    Module.concat(__MODULE__, "#{module_name}#{suffix}Schema")
  end

  # Create an inline schema from field specifications
  defp create_inline_schema(schema_module, field_specs) do
    quote do
      defmodule unquote(schema_module) do
        use Ecto.Schema
        import Ecto.Changeset

        @primary_key false
        embedded_schema do
          (unquote_splicing(parse_schema_fields(field_specs)))
        end

        def changeset(struct, params) do
          unquote(parse_changeset_logic(field_specs))
        end
      end
    end
  end

  # Parse inline schema fields into Ecto field definitions
  defp parse_schema_fields(field_specs) when is_list(field_specs) do
    Enum.map(field_specs, fn {field_name, field_spec} ->
      {type, opts} = parse_field_spec(field_spec)

      if opts[:default] do
        quote do: field(unquote(field_name), unquote(type), default: unquote(opts[:default]))
      else
        quote do: field(unquote(field_name), unquote(type))
      end
    end)
  end

  defp parse_schema_fields(_), do: []

  # Parse field specification - handles both [type, opt1, opt2] and just :type formats
  defp parse_field_spec([type | opts]) when is_atom(type) do
    parsed_opts = parse_field_opts(opts, %{})
    {type, parsed_opts}
  end

  defp parse_field_spec(type) when is_atom(type) do
    {type, %{}}
  end

  defp parse_field_spec({type, subtype}) do
    {{type, subtype}, %{}}
  end

  # Parse field options from keyword-style list
  defp parse_field_opts([], acc), do: acc

  defp parse_field_opts([{key, value} | rest], acc) do
    parse_field_opts(rest, Map.put(acc, key, value))
  end

  defp parse_field_opts([key | rest], acc) when is_atom(key) do
    parse_field_opts(rest, Map.put(acc, key, true))
  end

  # Generate changeset logic from inline field specifications
  defp parse_changeset_logic(field_specs) when is_list(field_specs) do
    fields_and_opts =
      Enum.map(field_specs, fn {field_name, field_spec} ->
        {_, opts} = parse_field_spec(field_spec)
        {field_name, opts}
      end)

    all_fields = Enum.map(fields_and_opts, fn {field_name, _} -> field_name end)

    required_fields =
      fields_and_opts
      |> Enum.filter(fn {_, opts} -> opts[:required] end)
      |> Enum.map(fn {field_name, _} -> field_name end)

    validations =
      Enum.flat_map(fields_and_opts, fn {field_name, opts} ->
        build_field_validations(field_name, opts)
      end)

    quote do
      struct
      |> cast(params, unquote(all_fields))
      |> validate_required(unquote(required_fields))
      |> then(fn changeset ->
        (unquote_splicing(validations))
      end)
    end
  end

  defp parse_changeset_logic(_) do
    quote do
      struct
      |> cast(params, [])
    end
  end

  # Build validations for a specific field based on its options
  defp build_field_validations(field_name, opts) do
    validations = []

    # Enum validation
    validations =
      if opts[:enum] do
        [
          quote(do: validate_inclusion(changeset, unquote(field_name), unquote(opts[:enum])))
          | validations
        ]
      else
        validations
      end

    # Length validations
    validations =
      if opts[:min_length] do
        [
          quote(
            do: validate_length(changeset, unquote(field_name), min: unquote(opts[:min_length]))
          )
          | validations
        ]
      else
        validations
      end

    validations =
      if opts[:max_length] do
        [
          quote(
            do: validate_length(changeset, unquote(field_name), max: unquote(opts[:max_length]))
          )
          | validations
        ]
      else
        validations
      end

    # Number validations
    validations =
      if opts[:min] do
        [
          quote(
            do:
              validate_number(changeset, unquote(field_name),
                greater_than_or_equal_to: unquote(opts[:min])
              )
          )
          | validations
        ]
      else
        validations
      end

    validations =
      if opts[:max] do
        [
          quote(
            do:
              validate_number(changeset, unquote(field_name),
                less_than_or_equal_to: unquote(opts[:max])
              )
          )
          | validations
        ]
      else
        validations
      end

    # Return changeset if no validations, otherwise pipe through validations
    case validations do
      [] -> [quote(do: changeset)]
      _ -> validations ++ [quote(do: changeset)]
    end
  end

  # Delegate to the specialized modules for backward compatibility
  defdelegate validate_input(tool, params), to: Validation
  defdelegate validate_output(tool, result), to: Validation
  defdelegate get_input_schema(tool), to: Validation
  defdelegate get_output_schema(tool), to: Validation
  defdelegate parse_input_json(tool, json_string), to: Validation
  defdelegate parse_output_json(tool, json_string), to: Validation

  defdelegate generate_input_json_schema(tool), to: JSONSchema
  defdelegate generate_output_json_schema(tool), to: JSONSchema
  defdelegate generate_tool_json_schema(tool), to: JSONSchema
end
