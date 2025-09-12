defmodule Dantex.Tool.JSONSchema do
  @moduledoc """
  Handles JSON Schema generation for Dantex tools.
  
  This module provides functionality to convert Ecto schemas to JSON Schema
  format for use with OpenAI, Ollama, and other function calling APIs.
  """

  alias Dantex.JSONSchema
  alias Dantex.Tool.Validation

  @doc """
  Generates JSON Schema for a tool's input schema.
  """
  def generate_input_json_schema(tool) do
    case Validation.get_input_schema(tool) do
      nil -> Jason.encode!(%{type: "object", properties: %{}})
      schema -> JSONSchema.from_ecto_schema(schema)
    end
  end

  @doc """
  Generates a complete JSON Schema for the tool to be used with OpenAI or Ollama function calling.
  """
  def generate_tool_json_schema(tool) do
    # Get the tool name and description from the module
    name = tool.tool_name()
    description = tool.tool_description()

    input_schema = Validation.get_input_schema(tool)

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
end