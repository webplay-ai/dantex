defmodule Dantex.Tool.MCP.SchemaConverter do
  @moduledoc """
  Converts JSON Schema definitions from MCP tools to Ecto schemas for validation.
  
  This module handles the translation between JSON Schema (used by MCP) and Ecto embedded schemas
  (used by Dantex for validation). It supports most common JSON Schema features including:
  
  - Basic types (string, number, integer, boolean, array, object)
  - Required fields
  - Default values  
  - String constraints (minLength, maxLength, enum)
  - Number constraints (minimum, maximum)
  - Nested objects and arrays
  """
  
  require Logger
  
  @doc """
  Converts a JSON Schema to a dynamically generated Ecto schema module.
  
  ## Parameters
  
    * `tool_name` - Name of the tool (used for module naming)
    * `json_schema` - JSON Schema definition from MCP tool
    
  ## Returns
  
    * `module()` - Generated Ecto schema module
    * `nil` - If schema is nil or empty
    
  ## Example
  
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "minLength" => 1},
          "age" => %{"type" => "integer", "minimum" => 0}
        },
        "required" => ["name"]
      }
      
      module = SchemaConverter.convert_json_schema_to_ecto("test_tool", schema)
  """
  def convert_json_schema_to_ecto(tool_name, json_schema) do
    case json_schema do
      nil -> nil
      schema when schema == %{} -> nil
      schema when is_map(schema) ->
        generate_ecto_schema_module(tool_name, schema)
      _ ->
        Logger.warning("Invalid JSON schema for tool #{tool_name}: #{inspect(json_schema)}")
        nil
    end
  end
  
  # Generate a dynamic Ecto schema module
  defp generate_ecto_schema_module(tool_name, json_schema) do
    module_name = create_schema_module_name(tool_name)
    
    try do
      # Parse the JSON schema
      properties = case json_schema["properties"] do
        props when is_map(props) -> props
        _ -> %{}
      end
      required = case json_schema["required"] do
        req when is_list(req) -> req
        _ -> []
      end
      
      # Generate field definitions
      field_definitions = parse_properties(properties)
      
      # Generate changeset validations
      validations = generate_validations(properties, required)
      
      # Build the complete validation pipeline
      pipeline = build_validation_pipeline(validations)
      
      # Create the module
      Module.create(module_name, quote do
        use Ecto.Schema
        import Ecto.Changeset
        
        @primary_key false
        embedded_schema do
          unquote_splicing(field_definitions)
        end
        
        def changeset(struct, params) do
          all_fields = unquote(Enum.map(Map.keys(properties), &String.to_atom/1))
          required_fields = unquote(Enum.map(required, &String.to_atom/1))
          
          unquote(pipeline)
        end
      end, Macro.Env.location(__ENV__))
      
      module_name
    rescue
      error ->
        Logger.error("Failed to generate schema for #{tool_name}: #{Exception.message(error)}")
        nil
    end
  end
  
  # Create a unique module name for the schema
  defp create_schema_module_name(tool_name) do
    sanitized_name = 
      tool_name
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> Macro.camelize()
    
    Module.concat([Dantex.Tool.MCP.GeneratedSchemas, "#{sanitized_name}InputSchema"])
  end
  
  # Parse JSON Schema properties into Ecto field definitions
  defp parse_properties(properties) when is_map(properties) do
    Enum.map(properties, fn {field_name, field_schema} ->
      field_atom = String.to_atom(field_name)
      {ecto_type, default_value} = json_type_to_ecto_type(field_schema)
      
      if default_value do
        quote do: field(unquote(field_atom), unquote(ecto_type), default: unquote(default_value))
      else
        quote do: field(unquote(field_atom), unquote(ecto_type))
      end
    end)
  end
  
  defp parse_properties(_), do: []
  
  # Convert JSON Schema types to Ecto types
  defp json_type_to_ecto_type(field_schema) when is_map(field_schema) do
    type = field_schema["type"]
    default = field_schema["default"]
    
    ecto_type = case type do
      "string" -> :string
      "integer" -> :integer
      "number" -> :float
      "boolean" -> :boolean
      "array" -> {:array, :string}  # Simplified - could be more complex
      "object" -> :map
      _ -> :string  # Fallback
    end
    
    {ecto_type, default}
  end
  
  defp json_type_to_ecto_type(_), do: {:string, nil}
  
  # Generate changeset validations from JSON Schema constraints
  defp generate_validations(properties, _required) when is_map(properties) do
    properties
    |> Enum.flat_map(fn {field_name, field_schema} ->
      field_atom = String.to_atom(field_name)
      generate_field_validations(field_atom, field_schema)
    end)
  end
  
  defp generate_validations(_, _), do: []
  
  # Generate validations for a specific field
  defp generate_field_validations(field_atom, field_schema) when is_map(field_schema) do
    validations = []
    
    # String length validations
    validations = 
      if field_schema["minLength"] do
        min_length = field_schema["minLength"]
        [quote(do: validate_length(unquote(field_atom), min: unquote(min_length))) | validations]
      else
        validations
      end
    
    validations =
      if field_schema["maxLength"] do
        max_length = field_schema["maxLength"]
        [quote(do: validate_length(unquote(field_atom), max: unquote(max_length))) | validations]
      else
        validations
      end
    
    # Enum validations
    validations =
      if field_schema["enum"] do
        enum_values = field_schema["enum"]
        [quote(do: validate_inclusion(unquote(field_atom), unquote(enum_values))) | validations]
      else
        validations
      end
    
    # Number validations
    validations =
      if field_schema["minimum"] do
        minimum = field_schema["minimum"]
        [quote(do: validate_number(unquote(field_atom), greater_than_or_equal_to: unquote(minimum))) | validations]
      else
        validations
      end
    
    validations =
      if field_schema["maximum"] do
        maximum = field_schema["maximum"]
        [quote(do: validate_number(unquote(field_atom), less_than_or_equal_to: unquote(maximum))) | validations]
      else
        validations
      end
    
    # Pattern validations (regex)
    validations =
      if field_schema["pattern"] do
        pattern = field_schema["pattern"]
        case Regex.compile(pattern) do
          {:ok, compiled_regex} ->
            [quote(do: validate_format(unquote(field_atom), unquote(Macro.escape(compiled_regex)))) | validations]
          {:error, _} ->
            Logger.warning("Invalid regex pattern for field #{field_atom}: #{pattern}")
            validations
        end
      else
        validations
      end
    
    validations
  end
  
  defp generate_field_validations(_, _), do: []
  
  # Build the validation pipeline by chaining all validations
  defp build_validation_pipeline(validations) do
    base_pipeline = quote do
      struct
      |> cast(params, all_fields)
      |> validate_required(required_fields)
    end
    
    case validations do
      [] -> base_pipeline
      _ ->
        Enum.reduce(validations, base_pipeline, fn validation, acc ->
          quote do: unquote(acc) |> unquote(validation)
        end)
    end
  end
  
  @doc """
  Converts an Ecto schema back to JSON Schema format.
  
  This is useful for generating OpenAI function calling schemas from MCP tools.
  """
  def ecto_schema_to_json_schema(schema_module) when is_atom(schema_module) do
    try do
      # This is a simplified conversion - in practice you might want to store
      # the original JSON schema and reuse it
      %{
        "type" => "object",
        "properties" => extract_properties_from_ecto(schema_module),
        "required" => extract_required_from_ecto(schema_module)
      }
    rescue
      _ -> %{"type" => "object", "properties" => %{}}
    end
  end
  
  # Extract properties from Ecto schema (simplified)
  defp extract_properties_from_ecto(schema_module) do
    try do
      if function_exported?(schema_module, :__schema__, 1) do
        fields = schema_module.__schema__(:fields)
        
        Enum.reduce(fields, %{}, fn field, acc ->
          type = schema_module.__schema__(:type, field)
          json_type = ecto_type_to_json_type(type)
          Map.put(acc, Atom.to_string(field), %{"type" => json_type})
        end)
      else
        %{}
      end
    rescue
      _ -> %{}
    end
  end
  
  # Extract required fields (simplified - assumes all fields without defaults are required)
  defp extract_required_from_ecto(schema_module) do
    try do
      if function_exported?(schema_module, :__schema__, 1) do
        fields = schema_module.__schema__(:fields)
        Enum.map(fields, &Atom.to_string/1)
      else
        []
      end
    rescue
      _ -> []
    end
  end
  
  # Convert Ecto types back to JSON Schema types
  defp ecto_type_to_json_type(:string), do: "string"
  defp ecto_type_to_json_type(:integer), do: "integer"
  defp ecto_type_to_json_type(:float), do: "number"
  defp ecto_type_to_json_type(:boolean), do: "boolean"
  defp ecto_type_to_json_type({:array, _}), do: "array"
  defp ecto_type_to_json_type(:map), do: "object"
  defp ecto_type_to_json_type(_), do: "string"
end