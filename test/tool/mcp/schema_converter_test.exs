defmodule Dantex.Tool.MCP.SchemaConverterTest do
  use ExUnit.Case

  alias Dantex.Tool.MCP.SchemaConverter

  describe "convert_json_schema_to_ecto/2" do
    test "returns nil for nil input" do
      assert SchemaConverter.convert_json_schema_to_ecto("test_tool", nil) == nil
    end

    test "returns nil for empty map input" do
      assert SchemaConverter.convert_json_schema_to_ecto("test_tool", %{}) == nil
    end

    test "returns nil for invalid input" do
      assert SchemaConverter.convert_json_schema_to_ecto("test_tool", "invalid") == nil
    end

    test "creates a valid Ecto schema module for simple string field" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"}
        },
        "required" => ["name"]
      }

      module = SchemaConverter.convert_json_schema_to_ecto("simple_test", json_schema)
      
      assert module != nil
      assert is_atom(module)
      
      # Test that the module exists and has the expected functions
      assert function_exported?(module, :changeset, 2)
      assert function_exported?(module, :__schema__, 1)
      
      # Test that we can create a changeset
      changeset = module.changeset(struct(module), %{name: "test"})
      assert changeset.valid?
      
      # Test required field validation
      changeset = module.changeset(struct(module), %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "creates schema with multiple field types" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "score" => %{"type" => "number"},
          "active" => %{"type" => "boolean"},
          "tags" => %{"type" => "array"},
          "metadata" => %{"type" => "object"}
        },
        "required" => ["name", "age"]
      }

      module = SchemaConverter.convert_json_schema_to_ecto("multi_type_test", json_schema)
      
      assert module != nil
      
      # Test valid data
      changeset = module.changeset(struct(module), %{
        name: "John",
        age: 30,
        score: 95.5,
        active: true,
        tags: ["elixir", "testing"],
        metadata: %{"key" => "value"}
      })
      assert changeset.valid?
      
      # Test required field validation
      changeset = module.changeset(struct(module), %{name: "John"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).age
    end

    test "creates schema with default values" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "status" => %{"type" => "string", "default" => "active"},
          "count" => %{"type" => "integer", "default" => 0}
        },
        "required" => ["name"]
      }

      module = SchemaConverter.convert_json_schema_to_ecto("default_test", json_schema)
      
      assert module != nil
      
      # Create struct and check defaults
      struct_instance = struct(module)
      assert struct_instance.status == "active"
      assert struct_instance.count == 0
    end

    test "creates schema with string validations" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "username" => %{
            "type" => "string",
            "minLength" => 3,
            "maxLength" => 20
          },
          "email" => %{
            "type" => "string",
            "pattern" => "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
          },
          "status" => %{
            "type" => "string",
            "enum" => ["active", "inactive", "pending"]
          }
        },
        "required" => ["username", "email"]
      }

      module = SchemaConverter.convert_json_schema_to_ecto("validation_test", json_schema)
      
      assert module != nil
      
      # Test valid data
      changeset = module.changeset(struct(module), %{
        username: "john_doe",
        email: "john@example.com",
        status: "active"
      })
      assert changeset.valid?
      
      # Test minLength validation
      changeset = module.changeset(struct(module), %{
        username: "jo",
        email: "john@example.com"
      })
      refute changeset.valid?
      assert "should be at least 3 character(s)" in errors_on(changeset).username
      
      # Test maxLength validation
      changeset = module.changeset(struct(module), %{
        username: "very_long_username_that_exceeds_limit",
        email: "john@example.com"
      })
      refute changeset.valid?
      assert "should be at most 20 character(s)" in errors_on(changeset).username
      
      # Test pattern validation
      changeset = module.changeset(struct(module), %{
        username: "john_doe",
        email: "invalid-email"
      })
      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
      
      # Test enum validation
      changeset = module.changeset(struct(module), %{
        username: "john_doe",
        email: "john@example.com",
        status: "invalid"
      })
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "creates schema with number validations" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "age" => %{
            "type" => "integer",
            "minimum" => 0,
            "maximum" => 120
          },
          "score" => %{
            "type" => "number",
            "minimum" => 0.0
          }
        },
        "required" => ["age"]
      }

      module = SchemaConverter.convert_json_schema_to_ecto("number_validation_test", json_schema)
      
      assert module != nil
      
      # Test valid data
      changeset = module.changeset(struct(module), %{
        age: 25,
        score: 95.5
      })
      assert changeset.valid?
      
      # Test minimum validation
      changeset = module.changeset(struct(module), %{
        age: -1
      })
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).age
      
      # Test maximum validation
      changeset = module.changeset(struct(module), %{
        age: 150
      })
      refute changeset.valid?
      assert "must be less than or equal to 120" in errors_on(changeset).age
    end

    test "generates unique module names for different tools" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "value" => %{"type" => "string"}
        }
      }

      module1 = SchemaConverter.convert_json_schema_to_ecto("tool_one", json_schema)
      module2 = SchemaConverter.convert_json_schema_to_ecto("tool_two", json_schema)
      
      assert module1 != module2
      assert module1 != nil
      assert module2 != nil
    end

    test "sanitizes tool names for module creation" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "value" => %{"type" => "string"}
        }
      }

      # Test with special characters
      module = SchemaConverter.convert_json_schema_to_ecto("my-tool@v1.0", json_schema)
      assert module != nil
      assert is_atom(module)
    end
  end

  describe "ecto_schema_to_json_schema/1" do
    test "converts Ecto schema back to JSON schema" do
      # First create an Ecto schema
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "active" => %{"type" => "boolean"}
        },
        "required" => ["name"]
      }

      module = SchemaConverter.convert_json_schema_to_ecto("reverse_test", json_schema)
      
      # Convert back to JSON schema
      result = SchemaConverter.ecto_schema_to_json_schema(module)
      
      assert result["type"] == "object"
      assert is_map(result["properties"])
      assert is_list(result["required"])
      
      # Check that basic properties are preserved
      properties = result["properties"]
      assert properties["name"]["type"] == "string"
      assert properties["age"]["type"] == "integer"
      assert properties["active"]["type"] == "boolean"
    end

    test "handles invalid module gracefully" do
      result = SchemaConverter.ecto_schema_to_json_schema(NonExistentModule)
      
      assert result["type"] == "object"
      assert result["properties"] == %{}
    end

    test "handles non-schema module gracefully" do
      result = SchemaConverter.ecto_schema_to_json_schema(String)
      
      assert result["type"] == "object"
      assert result["properties"] == %{}
    end
  end

  describe "edge cases and error handling" do
    test "handles schema with no properties" do
      json_schema = %{
        "type" => "object"
      }

      module = SchemaConverter.convert_json_schema_to_ecto("empty_props_test", json_schema)
      
      assert module != nil
      
      # Should be able to create changeset with empty data
      changeset = module.changeset(struct(module), %{})
      assert changeset.valid?
    end

    test "handles properties that are not maps" do
      json_schema = %{
        "type" => "object",
        "properties" => "not_a_map"
      }

      module = SchemaConverter.convert_json_schema_to_ecto("invalid_props_test", json_schema)
      
      assert module != nil
      
      # Should handle gracefully
      changeset = module.changeset(struct(module), %{})
      assert changeset.valid?
    end

    test "handles field schema that is not a map" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "field1" => "not_a_map",
          "field2" => %{"type" => "string"}
        }
      }

      module = SchemaConverter.convert_json_schema_to_ecto("mixed_field_types_test", json_schema)
      
      assert module != nil
      
      # Should still work for valid fields
      changeset = module.changeset(struct(module), %{field2: "test"})
      assert changeset.valid?
    end

    test "handles unknown JSON types gracefully" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "unknown_field" => %{"type" => "unknown_type"}
        }
      }

      module = SchemaConverter.convert_json_schema_to_ecto("unknown_type_test", json_schema)
      
      assert module != nil
      
      # Should default to string type
      changeset = module.changeset(struct(module), %{unknown_field: "test"})
      assert changeset.valid?
    end

    test "handles malformed regex pattern gracefully" do
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "field" => %{
            "type" => "string",
            "pattern" => "["  # Invalid regex
          }
        }
      }

      # Should not crash, might return nil or handle gracefully
      result = SchemaConverter.convert_json_schema_to_ecto("invalid_regex_test", json_schema)
      
      # The result might be nil due to regex compilation error
      # This tests that the function doesn't crash
      assert result == nil or is_atom(result)
    end
  end

  # Helper function to extract changeset errors in a more readable format
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end