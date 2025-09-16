defmodule Dantex.ToolSchemaTest do
  use ExUnit.Case

  alias Dantex.Examples.WeatherTool

  describe "tool schema validation" do
    test "validates input parameters" do
      # Valid parameters
      assert {:ok, _result} = WeatherTool.call(%{location: "London", units: "metric", days: 3})

      # Invalid parameters (missing required location)
      assert {:error, _reason} = WeatherTool.call(%{units: "metric", days: 3})
    end

    test "generates JSON schema for input" do
      json_schema = Dantex.Tool.generate_input_json_schema(WeatherTool)
      assert is_binary(json_schema)

      # Parse the JSON to verify structure
      parsed = Jason.decode!(json_schema)
      assert parsed["type"] == "object"
      assert Map.has_key?(parsed["properties"], "location")
    end


    test "generates complete tool JSON schema for OpenAI/Ollama" do
      json_schema = Dantex.Tool.generate_tool_json_schema(WeatherTool)
      assert is_binary(json_schema)

      # Parse the JSON to verify structure
      parsed = Jason.decode!(json_schema)
      assert parsed["type"] == "function"
      assert parsed["function"]["name"] == "get_weather"
      assert parsed["function"]["description"] == "Get the weather forecast for a location"
      assert parsed["function"]["parameters"]["type"] == "object"
    end

    test "parses and validates JSON input" do
      json_input = ~s({"location": "Paris", "units": "imperial", "days": 5})
      assert {:ok, validated} = Dantex.Tool.parse_input_json(WeatherTool, json_input)
      assert validated.location == "Paris"
      assert validated.units == "imperial"
      assert validated.days == 5

      # Invalid JSON
      assert {:error, _} = Dantex.Tool.parse_input_json(WeatherTool, ~s({"units": "imperial"}))
    end

  end
end
