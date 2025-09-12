defmodule Dantex.Tool.Validation do
  @moduledoc """
  Handles input validation for Dantex tools.
  
  This module provides validation functionality using Ecto schemas,
  including helper functions to get schemas from tools and validate
  data against those schemas.
  """

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

  # Validates a map against an Ecto schema.
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
end