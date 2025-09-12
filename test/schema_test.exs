# To prevent race conditions
Code.ensure_loaded(Dantex.Examples.WeatherTool)

defmodule Dantex.SchemaTest do
  use ExUnit.Case

  alias Dantex.Examples.WeatherTool
  alias Dantex.Tool

  test "get_input_schema returns the correct schema for WeatherTool" do
    input_schema = Tool.get_input_schema(WeatherTool)
    assert input_schema != nil
    assert input_schema == Dantex.Examples.WeatherInputSchema
  end

  test "generate_input_json_schema works correctly for WeatherTool" do
    schema_json = Tool.generate_input_json_schema(WeatherTool)
    assert schema_json != nil
    assert is_binary(schema_json)

    # Parse the JSON to ensure it's valid
    decoded = Jason.decode!(schema_json)
    assert decoded["type"] == "object"
    assert Map.has_key?(decoded, "properties")

    # Check that the properties match what we expect
    properties = decoded["properties"]
    assert Map.has_key?(properties, "location")
    assert Map.has_key?(properties, "days")
  end
end
