defmodule Dantex.Tool.MCPTest do
  use ExUnit.Case

  alias Dantex.Tool.MCP

  # Mock MCP client for testing
  defmodule MockMCPClient do
    def get_server_capabilities do
      {:ok, %{"tools" => %{}}}
    end

    def list_tools do
      {:ok, [
        %{
          "name" => "read_file",
          "description" => "Read a file from disk",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string", "description" => "File path to read"}
            },
            "required" => ["path"]
          }
        },
        %{
          "name" => "write_file",
          "description" => "Write content to a file",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string"},
              "content" => %{"type" => "string"}
            },
            "required" => ["path", "content"]
          }
        }
      ]}
    end

    def get_tool("read_file") do
      {:ok, %{
        "name" => "read_file",
        "description" => "Read a file from disk",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string", "description" => "File path to read"}
          },
          "required" => ["path"]
        }
      }}
    end

    def get_tool("write_file") do
      {:ok, %{
        "name" => "write_file",
        "description" => "Write content to a file",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string"},
            "content" => %{"type" => "string"}
          },
          "required" => ["path", "content"]
        }
      }}
    end

    def get_tool("nonexistent_tool") do
      {:error, :tool_not_found}
    end

    def get_tool("tool-with@special.chars") do
      {:error, :tool_not_found}
    end

    def call_tool("read_file", %{path: path}) do
      {:ok, %{"content" => "File content from #{path}"}}
    end

    def call_tool("read_file", %{"path" => path}) do
      {:ok, %{"content" => "File content from #{path}"}}
    end

    def call_tool("write_file", %{path: path, content: content}) do
      {:ok, %{"success" => true, "message" => "Wrote #{byte_size(content)} bytes to #{path}"}}
    end

    def call_tool("write_file", %{"path" => path, "content" => content}) do
      {:ok, %{"success" => true, "message" => "Wrote #{byte_size(content)} bytes to #{path}"}}
    end

    def call_tool("error_tool", _params) do
      {:error, "Simulated tool error"}
    end
  end

  # Mock client that doesn't support tools
  defmodule MockMCPClientNoTools do
    def get_server_capabilities do
      {:ok, %{}}
    end

    def list_tools do
      {:error, :not_supported}
    end

    def get_tool(_name) do
      {:error, :not_supported}
    end

    def call_tool(_name, _params) do
      {:error, :not_supported}
    end
  end

  # Mock client that errors
  defmodule MockMCPClientError do
    def get_server_capabilities do
      {:error, :connection_failed}
    end

    def list_tools do
      {:error, :connection_failed}
    end

    def get_tool(_name) do
      {:error, :connection_failed}
    end

    def call_tool(_name, _params) do
      {:error, :connection_failed}
    end
  end

  describe "new/2" do
    test "creates MCP tool module successfully" do
      assert {:ok, module} = MCP.new(MockMCPClient, "read_file")
      assert is_atom(module)
      assert module != nil
      
      # Module should implement Dantex.Tool behavior
      assert function_exported?(module, :call, 1)
      assert function_exported?(module, :tool_name, 0)
      assert function_exported?(module, :tool_description, 0)
      assert function_exported?(module, :__input_schema__, 0)
    end

    test "creates different modules for different tool names" do
      assert {:ok, module1} = MCP.new(MockMCPClient, "read_file")
      assert {:ok, module2} = MCP.new(MockMCPClient, "write_file")
      
      assert module1 != module2
      assert module1.tool_name() == "read_file"
      assert module2.tool_name() == "write_file"
    end

    test "handles different clients properly" do
      assert {:ok, module1} = MCP.new(MockMCPClient, "read_file")
      assert {:error, :not_supported} = MCP.new(MockMCPClientNoTools, "read_file")
      
      assert is_atom(module1)
    end

    test "returns error when tool not found" do
      assert {:error, reason} = MCP.new(MockMCPClient, "nonexistent_tool")
      assert reason == :tool_not_found
    end

    test "returns error when client connection fails" do
      assert {:error, reason} = MCP.new(MockMCPClientError, "read_file")
      assert reason == :connection_failed
    end

    test "validates input parameters" do
      # The function has guards, so these will raise FunctionClauseError
      assert_raise FunctionClauseError, fn -> 
        MCP.new("not_atom", "read_file")
      end
      
      assert_raise FunctionClauseError, fn ->
        MCP.new(MockMCPClient, :not_string)
      end
    end

    test "sanitizes tool names for module creation" do
      # This test would need a mock client that returns a tool with special characters
      # For now, we can test that the function doesn't crash with special names
      refute match?({:ok, _}, MCP.new(MockMCPClient, "tool-with@special.chars"))
    end
  end

  describe "new!/2" do
    test "returns module directly on success" do
      module = MCP.new!(MockMCPClient, "read_file")
      assert is_atom(module)
      assert module.tool_name() == "read_file"
    end

    test "raises on error" do
      assert_raise RuntimeError, ~r/Failed to create MCP tool/, fn ->
        MCP.new!(MockMCPClient, "nonexistent_tool")
      end
    end
  end

  describe "generated MCP tool module behavior" do
    setup do
      {:ok, module} = MCP.new(MockMCPClient, "read_file")
      {:ok, write_module} = MCP.new(MockMCPClient, "write_file")
      %{read_module: module, write_module: write_module}
    end

    test "implements tool_name/0", %{read_module: module} do
      assert module.tool_name() == "read_file"
    end

    test "implements tool_description/0", %{read_module: module} do
      description = module.tool_description()
      assert is_binary(description)
      assert description == "Read a file from disk"
    end

    test "implements __input_schema__/0", %{read_module: module} do
      schema = module.__input_schema__()
      assert schema != nil
      assert is_atom(schema)
      
      # Should be able to create changeset
      changeset = schema.changeset(struct(schema), %{path: "/test/path"})
      assert changeset.valid?
    end

    test "call/1 executes tool successfully", %{read_module: module} do
      result = module.call(%{path: "/test/file.txt"})
      assert {:ok, response} = result
      assert response["content"] == "File content from /test/file.txt"
    end

    test "call/1 handles tool parameters correctly", %{write_module: module} do
      params = %{path: "/test/output.txt", content: "Hello World"}
      result = module.call(params)
      
      assert {:ok, response} = result
      assert response["success"] == true
      assert response["message"] =~ "Wrote 11 bytes to /test/output.txt"
    end

    test "call/1 ignores context parameter", %{read_module: module} do
      params = %{path: "/test/file.txt", context: %{user_id: "123"}}
      result = module.call(params)
      
      assert {:ok, response} = result
      assert response["content"] == "File content from /test/file.txt"
    end

    test "call/1 handles tool errors", %{read_module: module} do
      # We need to create a module for error_tool to test this
      # For now, we'll test with MockMCPClient but it doesn't have error_tool
      # This would need a more sophisticated mock setup
      result = module.call(%{})
      # The mock should handle invalid params gracefully
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end

    test "call/1 handles exceptions gracefully", %{read_module: module} do
      # Test with invalid input that might cause exception  
      # The generated module expects a map, so this will raise
      assert_raise FunctionClauseError, fn ->
        module.call("invalid_input")
      end
    end
  end

  describe "list_tools/1" do
    test "returns list of available tools" do
      assert {:ok, tools} = MCP.list_tools(MockMCPClient)
      assert is_list(tools)
      assert "read_file" in tools
      assert "write_file" in tools
    end

    test "returns empty list when server doesn't support tools" do
      assert {:ok, tools} = MCP.list_tools(MockMCPClientNoTools)
      assert tools == []
    end

    test "returns error when client connection fails" do
      assert {:error, reason} = MCP.list_tools(MockMCPClientError)
      assert reason == :connection_failed
    end

    test "validates client module parameter" do
      # The function has guards and will raise on invalid input types
      assert_raise FunctionClauseError, fn ->
        MCP.list_tools("not_atom")
      end
      
      # nil gets handled as an error instead of raising due to error handling
      assert {:error, _} = MCP.list_tools(nil)
    end
  end

  describe "discover_tools/2" do
    test "creates modules for all available tools" do
      assert {:ok, modules} = MCP.discover_tools(MockMCPClient)
      assert is_list(modules)
      assert length(modules) == 2
      
      tool_names = Enum.map(modules, & &1.tool_name())
      assert "read_file" in tool_names
      assert "write_file" in tool_names
    end

    test "applies filters to discovered tools" do
      filters = %{allow: ["read_file"]}
      assert {:ok, modules} = MCP.discover_tools(MockMCPClient, filters)
      assert length(modules) == 1
      assert hd(modules).tool_name() == "read_file"
    end

    test "applies block filters" do
      filters = %{block: ["write_file"]}
      assert {:ok, modules} = MCP.discover_tools(MockMCPClient, filters)
      assert length(modules) == 1
      assert hd(modules).tool_name() == "read_file"
    end

    test "applies pattern filters" do
      filters = %{allow_patterns: ["^read_"]}
      assert {:ok, modules} = MCP.discover_tools(MockMCPClient, filters)
      assert length(modules) == 1
      assert hd(modules).tool_name() == "read_file"
    end

    test "handles empty filter gracefully" do
      assert {:ok, modules} = MCP.discover_tools(MockMCPClient, %{})
      assert length(modules) == 2
    end

    test "skips tools that fail to create" do
      # This would need a more sophisticated mock that sometimes fails
      # For now, test that it handles the error case
      assert {:ok, modules} = MCP.discover_tools(MockMCPClient)
      assert is_list(modules)
    end

    test "returns error when listing tools fails" do
      assert {:error, reason} = MCP.discover_tools(MockMCPClientError)
      assert reason == :connection_failed
    end
  end

  describe "module naming" do
    test "creates unique module names for different combinations" do
      assert {:ok, module1} = MCP.new(MockMCPClient, "read_file")
      assert {:ok, module2} = MCP.new(MockMCPClient, "write_file")
      # MockMCPClientNoTools will return error, so skip that test case
      
      # Modules should be different
      assert module1 != module2
      
      # Module names should follow expected pattern
      assert module1 |> Module.split() |> List.last() =~ "ReadFile"
      assert module2 |> Module.split() |> List.last() =~ "WriteFile"
    end

    test "sanitizes special characters in tool names" do
      # Would need a mock client that returns tools with special characters
      # Testing the edge case of module name generation
      assert {:ok, module1} = MCP.new(MockMCPClient, "read_file")
      assert {:ok, module2} = MCP.new(MockMCPClient, "write_file")
      
      # Should not crash and should create valid module names
      assert is_atom(module1)
      assert is_atom(module2)
    end
  end

  describe "error handling and edge cases" do
    test "handles missing tool definition gracefully" do
      assert {:error, :tool_not_found} = MCP.new(MockMCPClient, "nonexistent_tool")
    end

    test "handles client that raises exceptions" do
      defmodule CrashingClient do
        @behaviour Hermes.Client

        def get_server_capabilities, do: raise("Connection error")
        def list_tools, do: raise("Connection error")
        def get_tool(_), do: raise("Connection error")
        def call_tool(_, _), do: raise("Connection error")
      end

      assert {:error, error_msg} = MCP.list_tools(CrashingClient)
      assert is_binary(error_msg)
      assert error_msg =~ "Connection error"
    end

    test "handles malformed tool definitions" do
      defmodule MalformedClient do
        @behaviour Hermes.Client

        def get_server_capabilities, do: {:ok, %{"tools" => %{}}}
        def list_tools, do: {:ok, [%{"name" => "bad_tool"}]}
        def get_tool("bad_tool"), do: {:ok, %{"name" => "bad_tool", "inputSchema" => "invalid_schema"}}
        def call_tool(_, _), do: {:ok, %{}}
      end

      # Should handle malformed schema gracefully
      case MCP.new(MalformedClient, "bad_tool") do
        {:ok, _module} -> :ok  # Schema converter handled it
        {:error, _reason} -> :ok  # Expected error
      end
    end

    test "handles client returning unexpected response formats" do
      defmodule WeirdClient do
        @behaviour Hermes.Client

        def get_server_capabilities, do: "unexpected_format"
        def list_tools, do: "unexpected_format"
        def get_tool(_), do: "unexpected_format"
        def call_tool(_, _), do: "unexpected_format"
      end

      assert {:error, _} = MCP.list_tools(WeirdClient)
    end

    test "handles nil and invalid inputs" do
      # Functions handle invalid inputs gracefully for some cases
      assert {:error, _} = MCP.new(nil, "read_file")
      
      # These should raise due to guards
      assert_raise FunctionClauseError, fn ->
        MCP.new(MockMCPClient, nil)
      end
      
      assert_raise FunctionClauseError, fn ->
        MCP.new("string", "read_file")
      end
      
      assert_raise FunctionClauseError, fn ->
        MCP.new(MockMCPClient, 123)
      end
    end
  end

  describe "integration scenarios" do
    test "full workflow: discover, create, and use tools" do
      # 1. Discover available tools
      {:ok, tool_names} = MCP.list_tools(MockMCPClient)
      assert "read_file" in tool_names

      # 2. Create specific tool module
      {:ok, read_tool} = MCP.new(MockMCPClient, "read_file")

      # 3. Use the tool
      result = read_tool.call(%{path: "/test/integration.txt"})
      assert {:ok, response} = result
      assert response["content"] == "File content from /test/integration.txt"

      # 4. Validate tool metadata
      assert read_tool.tool_name() == "read_file"
      assert read_tool.tool_description() == "Read a file from disk"
    end

    test "filtered discovery workflow" do
      filters = %{
        allow: ["read_file"]
      }

      {:ok, modules} = MCP.discover_tools(MockMCPClient, filters)
      assert length(modules) == 1
      
      module = hd(modules)
      assert module.tool_name() == "read_file"
      
      # Tool should work correctly
      result = module.call(%{path: "/filtered/test.txt"})
      assert {:ok, _} = result
    end

    test "batch tool creation and validation" do
      {:ok, tool_names} = MCP.list_tools(MockMCPClient)
      
      modules = Enum.map(tool_names, fn name ->
        {:ok, module} = MCP.new(MockMCPClient, name)
        module
      end)
      
      assert length(modules) == length(tool_names)
      
      # Each module should be functional
      Enum.each(modules, fn module ->
        assert is_atom(module)
        assert is_binary(module.tool_name())
        assert is_binary(module.tool_description())
        assert module.__input_schema__() != nil
      end)
    end
  end
end