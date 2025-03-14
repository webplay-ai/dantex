defmodule Dantex.Tool.XMLAdapterBuildToolDocsTest do
  use ExUnit.Case

  alias Dantex.Tool.XMLAdapter

  describe "build_tool_docs/1" do
    test "generates XML documentation for a tool with input and output schemas" do
      # Use the example weather tool
      tools = [Dantex.Examples.WeatherTool]

      result = XMLAdapter.build_tool_docs(tools)

      # Check that the result contains the expected elements
      assert String.contains?(result, "# Tool: get_weather")
      assert String.contains?(result, "Get the weather forecast for a location")
      assert String.contains?(result, "<get_weather>")
      assert String.contains?(result, "<location>")
      assert String.contains?(result, "<units>")
      assert String.contains?(result, "<days>")
      assert String.contains?(result, "## Output Format")
      assert String.contains?(result, "<result>")
      assert String.contains?(result, "<location>")
      assert String.contains?(result, "<current_temp>")
      assert String.contains?(result, "<conditions>")
      assert String.contains?(result, "<forecast>")
    end

    test "generates documentation for multiple tools" do
      # Create a simple test tool
      defmodule TestTool do
        use Dantex.Tool.Basic

        @tool_name "test_tool"
        @tool_description "A test tool for testing"

        def do_call(_params) do
          {:ok, "test result"}
        end
      end

      tools = [Dantex.Examples.WeatherTool, TestTool]

      result = XMLAdapter.build_tool_docs(tools)

      # Check that both tools are included in the documentation
      assert String.contains?(result, "# Tool: get_weather")
      assert String.contains?(result, "# Tool: test_tool")
      assert String.contains?(result, "A test tool for testing")
    end

    test "handles tools without schemas" do
      # Create a tool without schemas
      defmodule NoSchemasTool do
        use Dantex.Tool.Basic

        @tool_name "no_schemas_tool"
        @tool_description "A tool without schemas"

        def do_call(_params) do
          {:ok, "result"}
        end
      end

      tools = [NoSchemasTool]

      result = XMLAdapter.build_tool_docs(tools)

      # Check that the documentation is generated correctly
      assert String.contains?(result, "# Tool: no_schemas_tool")
      assert String.contains?(result, "A tool without schemas")
      assert String.contains?(result, "<!-- No parameters required -->")
      assert String.contains?(result, "<!-- No specific output format -->")
    end
  end

end
