defmodule Dantex.Providers.TogetherTest do
  use ExUnit.Case, async: true

  alias Dantex.Providers.Together
  alias Dantex.Message

  describe "parse_choices/1" do
    test "handles standard tool_calls format with index field" do
      # Response format matching the Together AI spec with index field
      choices = [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => "I'll help you with that.",
            "tool_calls" => [
              %{
                "index" => 0,
                "id" => "call_abc123",
                "type" => "function",
                "function" => %{
                  "name" => "send_messages",
                  "arguments" => "{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}"
                }
              }
            ]
          }
        }
      ]

      result = Together.parse_choices(choices)

      assert [message] = result
      assert message.role == "assistant"
      assert message.content == "I'll help you with that."
      assert [tool_call] = message.tool_calls

      assert tool_call.id == "call_abc123"
      assert tool_call.type == "function"
      assert tool_call.function.name == "send_messages"
      assert tool_call.function.arguments == "{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}"
    end

    test "handles legacy function_call format" do
      # Some models might use the legacy function_call field
      choices = [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => "I'll call a function for you.",
            "function_call" => %{
              "name" => "get_weather",
              "arguments" => "{\"location\":\"San Francisco\"}"
            }
          }
        }
      ]

      result = Together.parse_choices(choices)

      assert [message] = result
      assert message.role == "assistant"
      assert message.content == "I'll call a function for you."
      assert [tool_call] = message.tool_calls

      # Should generate a unique ID for legacy format
      assert String.starts_with?(tool_call.id, "call_")
      assert tool_call.type == "function"
      assert tool_call.function.name == "get_weather"
      assert tool_call.function.arguments == "{\"location\":\"San Francisco\"}"
    end

    test "handles missing fields in tool_calls gracefully" do
      # Test robustness when API response is missing some fields
      choices = [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              %{
                # Missing "id" field
                "type" => "function",
                "function" => %{
                  "name" => "test_function"
                  # Missing "arguments" field
                }
              },
              %{
                "id" => "call_xyz789",
                # Missing "type" field
                "function" => %{
                  "name" => "another_function",
                  "arguments" => "{\"param\":\"value\"}"
                }
              }
            ]
          }
        }
      ]

      result = Together.parse_choices(choices)

      assert [message] = result
      assert message.role == "assistant"
      assert [tool_call1, tool_call2] = message.tool_calls

      # First tool call with missing fields should get defaults
      assert String.starts_with?(tool_call1.id, "call_")
      assert tool_call1.type == "function"
      assert tool_call1.function.name == "test_function"
      assert tool_call1.function.arguments == "{}"

      # Second tool call with some missing fields
      assert tool_call2.id == "call_xyz789"
      assert tool_call2.type == "function"
      assert tool_call2.function.name == "another_function"
      assert tool_call2.function.arguments == "{\"param\":\"value\"}"
    end

    test "handles completely malformed tool_calls" do
      # Test when tool_calls is present but not a list or contains invalid data
      choices = [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => "Some response",
            "tool_calls" => "not_a_list"
          }
        }
      ]

      result = Together.parse_choices(choices)

      assert [message] = result
      assert message.role == "assistant"
      assert message.content == "Some response"
      assert message.tool_calls == nil
    end

    test "handles missing function_call fields gracefully" do
      # Test legacy function_call with missing fields
      choices = [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => "Function call with missing data",
            "function_call" => %{
              # Missing "name" and "arguments" fields
            }
          }
        }
      ]

      result = Together.parse_choices(choices)

      assert [message] = result
      assert message.role == "assistant"
      assert [tool_call] = message.tool_calls

      assert String.starts_with?(tool_call.id, "call_")
      assert tool_call.type == "function"
      assert tool_call.function.name == "unknown_function"
      assert tool_call.function.arguments == "{}"
    end

    test "handles normal text responses without tool calls" do
      choices = [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => "Just a normal text response."
          }
        }
      ]

      result = Together.parse_choices(choices)

      assert [message] = result
      assert message.role == "assistant"
      assert message.content == "Just a normal text response."
      assert message.tool_calls == nil
    end

    test "handles multiple choices in response" do
      choices = [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => "First choice"
          }
        },
        %{
          "message" => %{
            "role" => "assistant",
            "content" => "Second choice"
          }
        }
      ]

      result = Together.parse_choices(choices)

      assert [message1, message2] = result
      assert message1.content == "First choice"
      assert message2.content == "Second choice"
    end
  end
end