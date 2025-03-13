defmodule Dantex.Tool.SchemaHelpers do
  @moduledoc """
  Helpers for defining and working with Ecto schemas in tools.
  """

  @doc """
  Registers an Ecto schema module as the input schema for a tool.
  """
  defmacro input_schema(schema_module) do
    quote do
      Module.put_attribute(__MODULE__, :input_schema, unquote(schema_module))
    end
  end

  @doc """
  Registers an Ecto schema module as the output schema for a tool.
  """
  defmacro output_schema(schema_module) do
    quote do
      Module.put_attribute(__MODULE__, :output_schema, unquote(schema_module))
    end
  end

  @doc """
  Defines a schema module within a tool module.
  """
  defmacro define_schema(name, schema_type, do: block) do
    schema_module =
      quote do
        defmodule unquote(name) do
          import Ecto.Changeset

          use Ecto.Schema

          @primary_key false
          embedded_schema do
            unquote(block)
          end

          def changeset(struct, params) do
            fields = __schema__(:fields)

            struct
            |> cast(params, fields)
            |> validate_required(fields)
          end
        end
      end

    register =
      case schema_type do
        :input ->
          quote do
            # Explicitly set the module attribute after the module is defined
            Module.register_attribute(__MODULE__, :input_schema, persist: true)
            @input_schema unquote(name)
            # Ensure the attribute is properly exported
            def __input_schema__, do: unquote(name)
          end
        :output ->
          quote do
            # Explicitly set the module attribute after the module is defined
            Module.register_attribute(__MODULE__, :output_schema, persist: true)
            @output_schema unquote(name)
            # Ensure the attribute is properly exported
            def __output_schema__, do: unquote(name)
          end
      end

    quote do
      unquote(schema_module)
      unquote(register)
    end
  end

  @doc """
  Defines an input schema module within a tool module.
  """
  defmacro define_input_schema(name, do: block) do
    quote do
      define_schema(unquote(name), :input) do
        unquote(block)
      end
    end
  end

  @doc """
  Defines an output schema module within a tool module.
  """
  defmacro define_output_schema(name, do: block) do
    quote do
      define_schema(unquote(name), :output) do
        unquote(block)
      end
    end
  end
end
