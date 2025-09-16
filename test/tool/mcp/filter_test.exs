defmodule Dantex.Tool.MCP.FilterTest do
  use ExUnit.Case

  alias Dantex.Tool.MCP.Filter

  @test_tools ["read_file", "write_file", "delete_file", "list_directory", "search_files", "create_backup"]

  describe "apply/2 basic behavior" do
    test "returns original tools when filters is empty map" do
      result = Filter.apply(@test_tools, %{})
      assert result == @test_tools
    end

    test "returns original tools when filters is not a map" do
      result = Filter.apply(@test_tools, nil)
      assert result == @test_tools

      result = Filter.apply(@test_tools, "invalid")
      assert result == @test_tools

      result = Filter.apply(@test_tools, 123)
      assert result == @test_tools
    end

    test "returns original tools when tools is not a list" do
      result = Filter.apply("invalid", %{allow: ["read_file"]})
      assert result == "invalid"

      result = Filter.apply(nil, %{allow: ["read_file"]})
      assert result == nil
    end
  end

  describe "apply/2 allow filter" do
    test "filters to only allowed tools" do
      filters = %{allow: ["read_file", "list_directory"]}
      result = Filter.apply(@test_tools, filters)
      assert result == ["read_file", "list_directory"]
    end

    test "returns empty list when no tools match allow list" do
      filters = %{allow: ["nonexistent_tool"]}
      result = Filter.apply(@test_tools, filters)
      assert result == []
    end

    test "returns empty list when allow list is empty" do
      filters = %{allow: []}
      result = Filter.apply(@test_tools, filters)
      assert result == []
    end

    test "ignores allow filter when not a list" do
      filters = %{allow: "not_a_list"}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end
  end

  describe "apply/2 block filter" do
    test "removes blocked tools" do
      filters = %{block: ["delete_file", "write_file"]}
      result = Filter.apply(@test_tools, filters)
      assert result == ["read_file", "list_directory", "search_files", "create_backup"]
    end

    test "returns original list when no tools match block list" do
      filters = %{block: ["nonexistent_tool"]}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end

    test "returns original list when block list is empty" do
      filters = %{block: []}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end

    test "ignores block filter when not a list" do
      filters = %{block: "not_a_list"}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end
  end

  describe "apply/2 allow_patterns filter" do
    test "filters to tools matching allowed patterns" do
      filters = %{allow_patterns: ["^read_", "^list_"]}
      result = Filter.apply(@test_tools, filters)
      assert result == ["read_file", "list_directory"]
    end

    test "supports multiple patterns" do
      filters = %{allow_patterns: ["file$", "directory$"]}
      result = Filter.apply(@test_tools, filters)
      assert result == ["read_file", "write_file", "delete_file", "list_directory"]
    end

    test "returns empty list when no tools match patterns" do
      filters = %{allow_patterns: ["^nonexistent"]}
      result = Filter.apply(@test_tools, filters)
      assert result == []
    end

    test "returns empty list when allow_patterns is empty" do
      filters = %{allow_patterns: []}
      result = Filter.apply(@test_tools, filters)
      assert result == []
    end

    test "ignores invalid regex patterns" do
      filters = %{allow_patterns: ["[invalid", "^read_"]}
      result = Filter.apply(@test_tools, filters)
      assert result == ["read_file"]
    end

    test "ignores allow_patterns filter when not a list" do
      filters = %{allow_patterns: "not_a_list"}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end
  end

  describe "apply/2 block_patterns filter" do
    test "removes tools matching blocked patterns" do
      filters = %{block_patterns: ["^delete_", "^write_"]}
      result = Filter.apply(@test_tools, filters)
      assert result == ["read_file", "list_directory", "search_files", "create_backup"]
    end

    test "supports multiple patterns" do
      filters = %{block_patterns: ["file$", "backup$"]}
      result = Filter.apply(@test_tools, filters)
      assert result == ["list_directory", "search_files"]
    end

    test "returns original list when no tools match patterns" do
      filters = %{block_patterns: ["^nonexistent"]}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end

    test "returns original list when block_patterns is empty" do
      filters = %{block_patterns: []}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end

    test "ignores invalid regex patterns" do
      filters = %{block_patterns: ["[invalid", "^delete_"]}
      result = Filter.apply(@test_tools, filters)
      assert result == ["read_file", "write_file", "list_directory", "search_files", "create_backup"]
    end

    test "ignores block_patterns filter when not a list" do
      filters = %{block_patterns: "not_a_list"}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end
  end

  describe "apply/2 security_level filter" do
    test "filters tools by security level" do
      # Mock the application config for this test
      Application.put_env(:dantex, :tool_security_levels, %{
        "read_file" => :safe,
        "write_file" => :moderate,
        "delete_file" => :dangerous,
        "list_directory" => :safe
      })

      filters = %{security_level: :safe}
      result = Filter.apply(["read_file", "write_file", "delete_file", "list_directory"], filters)
      assert result == ["read_file", "list_directory"]

      filters = %{security_level: :moderate}
      result = Filter.apply(["read_file", "write_file", "delete_file", "list_directory"], filters)
      assert result == ["read_file", "write_file", "list_directory"]

      filters = %{security_level: :dangerous}
      result = Filter.apply(["read_file", "write_file", "delete_file", "list_directory"], filters)
      assert result == ["read_file", "write_file", "delete_file", "list_directory"]

      # Clean up
      Application.delete_env(:dantex, :tool_security_levels)
    end

    test "defaults unknown tools to safe level" do
      Application.put_env(:dantex, :tool_security_levels, %{})

      filters = %{security_level: :safe}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools

      filters = %{security_level: :moderate}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools

      # Clean up
      Application.delete_env(:dantex, :tool_security_levels)
    end

    test "defaults invalid security levels to safe" do
      filters = %{security_level: :invalid_level}
      result = Filter.apply(@test_tools, filters)
      # Should only include tools with :safe level (defaults to all unknown tools)
      assert result == @test_tools
    end

    test "ignores security_level filter when not an atom" do
      filters = %{security_level: "not_an_atom"}
      result = Filter.apply(@test_tools, filters)
      assert result == @test_tools
    end
  end

  describe "apply/2 combined filters" do
    test "applies all filters in sequence" do
      filters = %{
        allow: ["read_file", "write_file", "delete_file", "list_directory"],
        block: ["delete_file"],
        block_patterns: ["^write_"]
      }
      result = Filter.apply(@test_tools, filters)
      assert result == ["read_file", "list_directory"]
    end

    test "allow filter takes precedence over other filters" do
      filters = %{
        allow: ["read_file", "write_file"],
        block: ["read_file"],
        block_patterns: ["^read_"]
      }
      result = Filter.apply(@test_tools, filters)
      # Block filters are applied after allow filter
      assert result == ["write_file"]
    end

    test "complex filtering scenario" do
      Application.put_env(:dantex, :tool_security_levels, %{
        "read_file" => :safe,
        "write_file" => :moderate,
        "delete_file" => :dangerous,
        "list_directory" => :safe,
        "search_files" => :moderate
      })

      filters = %{
        allow_patterns: ["file$", "directory$", "files$"],
        block: ["delete_file"],
        security_level: :moderate
      }
      result = Filter.apply(@test_tools, filters)
      # Should include: read_file (safe), write_file (moderate), list_directory (safe), search_files (moderate)
      # But exclude: delete_file (blocked), create_backup (doesn't match pattern)
      assert result == ["read_file", "write_file", "list_directory", "search_files"]

      # Clean up
      Application.delete_env(:dantex, :tool_security_levels)
    end
  end

  describe "merge/1" do
    test "merges multiple filter configurations" do
      config1 = %{allow: ["read_file"], block: ["delete_file"]}
      config2 = %{allow: ["read_file", "write_file"], security_level: :safe}
      config3 = %{block_patterns: ["^delete_"]}

      result = Filter.merge([config1, config2, config3])
      
      expected = %{
        allow: ["read_file", "write_file"],
        block: ["delete_file"],
        security_level: :safe,
        block_patterns: ["^delete_"]
      }
      
      assert result == expected
    end

    test "later configs override earlier ones" do
      config1 = %{allow: ["read_file"], security_level: :safe}
      config2 = %{allow: ["write_file"], security_level: :dangerous}

      result = Filter.merge([config1, config2])
      
      expected = %{
        allow: ["write_file"],
        security_level: :dangerous
      }
      
      assert result == expected
    end

    test "returns empty map for empty list" do
      result = Filter.merge([])
      assert result == %{}
    end

    test "returns single config when list has one element" do
      config = %{allow: ["read_file"], block: ["delete_file"]}
      result = Filter.merge([config])
      assert result == config
    end

    test "handles only valid map configs" do
      config1 = %{allow: ["read_file"]}
      config2 = %{security_level: :safe}
      config3 = %{block: ["delete_file"]}

      result = Filter.merge([config1, config2, config3])
      
      expected = %{
        allow: ["read_file"],
        security_level: :safe,
        block: ["delete_file"]
      }
      
      assert result == expected
    end
  end

  describe "validate/1" do
    test "returns :ok for valid filter configuration" do
      filters = %{
        allow: ["read_file", "write_file"],
        block: ["delete_file"],
        allow_patterns: ["^read_", "^list_"],
        block_patterns: ["^delete_", "^format_"],
        security_level: :safe
      }
      
      assert Filter.validate(filters) == :ok
    end

    test "returns :ok for empty map" do
      assert Filter.validate(%{}) == :ok
    end

    test "returns error when filters is not a map" do
      assert Filter.validate("not_a_map") == {:error, "Filters must be a map"}
      assert Filter.validate(nil) == {:error, "Filters must be a map"}
      assert Filter.validate(123) == {:error, "Filters must be a map"}
      assert Filter.validate([]) == {:error, "Filters must be a map"}
    end

    test "validates allow list" do
      assert Filter.validate(%{allow: ["read_file", "write_file"]}) == :ok
      assert Filter.validate(%{allow: []}) == :ok
      
      assert Filter.validate(%{allow: "not_a_list"}) == {:error, "allow must be a list"}
      assert Filter.validate(%{allow: [123, "read_file"]}) == {:error, "allow must be a list of strings"}
    end

    test "validates block list" do
      assert Filter.validate(%{block: ["delete_file", "format_disk"]}) == :ok
      assert Filter.validate(%{block: []}) == :ok
      
      assert Filter.validate(%{block: "not_a_list"}) == {:error, "block must be a list"}
      assert Filter.validate(%{block: ["delete_file", 456]}) == {:error, "block must be a list of strings"}
    end

    test "validates allow_patterns" do
      assert Filter.validate(%{allow_patterns: ["^read_", "file$"]}) == :ok
      assert Filter.validate(%{allow_patterns: []}) == :ok
      
      assert Filter.validate(%{allow_patterns: "not_a_list"}) == {:error, "allow_patterns must be a list of regex patterns"}
    end

    test "validates block_patterns" do
      assert Filter.validate(%{block_patterns: ["^delete_", "format_.*"]}) == :ok
      assert Filter.validate(%{block_patterns: []}) == :ok
      
      assert Filter.validate(%{block_patterns: "not_a_list"}) == {:error, "block_patterns must be a list of regex patterns"}
    end

    test "detects invalid regex patterns" do
      invalid_patterns = ["[invalid", "unclosed("]
      
      result = Filter.validate(%{allow_patterns: invalid_patterns})
      assert {:error, error_msg} = result
      assert error_msg =~ "allow_patterns contains invalid regex patterns"
      
      result = Filter.validate(%{block_patterns: invalid_patterns})
      assert {:error, error_msg} = result
      assert error_msg =~ "block_patterns contains invalid regex patterns"
    end

    test "detects non-string patterns" do
      result = Filter.validate(%{allow_patterns: ["valid_pattern", 123]})
      assert {:error, error_msg} = result
      assert error_msg =~ "allow_patterns contains invalid regex patterns"
    end

    test "validates valid security levels" do
      assert Filter.validate(%{security_level: :safe}) == :ok
      assert Filter.validate(%{security_level: :moderate}) == :ok
      assert Filter.validate(%{security_level: :dangerous}) == :ok
    end

    test "rejects invalid security levels" do
      result = Filter.validate(%{security_level: :invalid})
      assert {:error, error_msg} = result
      assert error_msg =~ "security_level must be one of [:safe, :moderate, :dangerous]"
      assert error_msg =~ ":invalid"
      
      result = Filter.validate(%{security_level: "safe"})
      assert {:error, error_msg} = result
      assert error_msg =~ "security_level must be one of [:safe, :moderate, :dangerous]"
    end

    test "validates multiple fields and returns first error" do
      filters = %{
        allow: "not_a_list",
        security_level: :invalid
      }
      
      result = Filter.validate(filters)
      assert {:error, "allow must be a list"} = result
    end

    test "validates all fields when no errors" do
      filters = %{
        allow: ["read_file"],
        block: ["delete_file"],
        allow_patterns: ["^read_"],
        block_patterns: ["^delete_"],
        security_level: :moderate
      }
      
      assert Filter.validate(filters) == :ok
    end
  end
end