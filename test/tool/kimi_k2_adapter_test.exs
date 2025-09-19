defmodule Dantex.Tool.KimiK2AdapterTest do
  use ExUnit.Case, async: true

  alias Dantex.Message
  alias Dantex.Tool.KimiK2Adapter

  describe "extract_tool_calls/1" do
    test "extracts single tool call from Kimi K2 format" do
      content = """
      I'll help you check the weather in Beijing today.

      <|tool_calls_section_begin|>
      <|tool_call_begin|>functions.get_weather:0<|tool_call_argument_begin|>{"location": "Beijing", "unit": "celsius"}<|tool_call_end|>
      <|tool_calls_section_end|>
      """

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      {:ok, result} = KimiK2Adapter.extract_tool_calls(message)

      assert result.role == "assistant"
      assert result.content == content

      assert [tool_call] = result.tool_calls
      assert tool_call.id == "functions.get_weather:0"
      assert tool_call.type == "function"
      assert tool_call.function.name == "get_weather"
      assert tool_call.function.arguments == ~s|{"location": "Beijing", "unit": "celsius"}|
    end

    test "extracts multiple tool calls from Kimi K2 format" do
      content = """
      I'll get the weather and then check your calendar.

      <|tool_calls_section_begin|>
      <|tool_call_begin|>functions.get_weather:0<|tool_call_argument_begin|>{"location": "Beijing", "unit": "celsius"}<|tool_call_end|>
      <|tool_call_begin|>functions.check_calendar:1<|tool_call_argument_begin|>{"date": "2025-01-15"}<|tool_call_end|>
      <|tool_calls_section_end|>
      """

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      {:ok, result} = KimiK2Adapter.extract_tool_calls(message)

      assert result.role == "assistant"
      assert result.content == content

      assert [tool_call1, tool_call2] = result.tool_calls

      assert tool_call1.id == "functions.get_weather:0"
      assert tool_call1.type == "function"
      assert tool_call1.function.name == "get_weather"
      assert tool_call1.function.arguments == ~s|{"location": "Beijing", "unit": "celsius"}|

      assert tool_call2.id == "functions.check_calendar:1"
      assert tool_call2.type == "function"
      assert tool_call2.function.name == "check_calendar"
      assert tool_call2.function.arguments == ~s|{"date": "2025-01-15"}|
    end

    test "returns empty tool_calls for content without tool calls" do
      content = "The weather in Beijing today is sunny with a temperature of 25°C."

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      {:ok, result} = KimiK2Adapter.extract_tool_calls(message)

      assert result.role == "assistant"
      assert result.content == content
      assert result.tool_calls == []
    end

    test "handles message with nil content" do
      message = %Message{role: "assistant", content: nil, tool_calls: nil}

      {:ok, result} = KimiK2Adapter.extract_tool_calls(message)

      assert result.role == "assistant"
      assert result.content == nil
      assert result.tool_calls == nil
    end

    test "handles malformed tool call sections gracefully" do
      content = """
      This has incomplete tool call markers.

      <|tool_calls_section_begin|>
      <|tool_call_begin|>functions.get_weather:0<|tool_call_argument_begin|>{"location": "Beijing"}
      """

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      {:ok, result} = KimiK2Adapter.extract_tool_calls(message)

      assert result.role == "assistant"
      assert result.content == content
      assert result.tool_calls == []
    end

    test "rejects OpenAI-style tool call IDs that don't follow Kimi K2 spec" do
      content = """
      This uses OpenAI-style IDs instead of Kimi K2 format.

      <|tool_calls_section_begin|>
      <|tool_call_begin|>call_fm453ztn8q6prph3igmryixt<|tool_call_argument_begin|>{"messages": [{"role": "user", "content": "test"}]}<|tool_call_end|>
      <|tool_calls_section_end|>
      """

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      {:ok, result} = KimiK2Adapter.extract_tool_calls(message)

      assert result.role == "assistant"
      assert result.content == content
      # OpenAI-style IDs don't match the strict Kimi K2 regex, so no tool calls are extracted
      assert result.tool_calls == []
    end

    test "reproduces the bug with mixed format - OpenAI style ID being used as function name" do
      # This reproduces the exact bug reported: LLM uses OpenAI-style tool call ID as function name
      content = """
      I'll help with that.

      <|tool_calls_section_begin|>
      <|tool_call_begin|>call_g984eya7rrq3zfn6ty68nh50<|tool_call_argument_begin|>{"messages":[{"content":"What are your capabilities? What can you help me with?","role":"user"}]}<|tool_call_end|>
      <|tool_calls_section_end|>
      """

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      {:ok, result} = KimiK2Adapter.extract_tool_calls(message)

      assert result.role == "assistant"
      assert result.content == content
      # Currently this would result in empty tool_calls, but ideally we want to handle this gracefully
      # The problem is that `call_g984eya7rrq3zfn6ty68nh50` doesn't match the `functions.tool_name:index` pattern
      assert result.tool_calls == []
    end

    test "debug - check what the current regex actually matches" do
      # Let's test different patterns to understand the current behavior
      func_call_pattern = ~r/<\|tool_call_begin\|>\s*(?<tool_call_id>[\w\.]+:\d+)\s*<\|tool_call_argument_begin\|>\s*(?<function_arguments>.*?)\s*<\|tool_call_end\|>/s

      # Test the expected pattern - should match
      good_content = "<|tool_call_begin|>functions.send_messages:0<|tool_call_argument_begin|>{\"test\": \"value\"}<|tool_call_end|>"
      good_matches = Regex.scan(func_call_pattern, good_content, capture: :all_names)
      assert length(good_matches) == 1

      # Test the problematic pattern - should NOT match
      bad_content = "<|tool_call_begin|>call_g984eya7rrq3zfn6ty68nh50<|tool_call_argument_begin|>{\"test\": \"value\"}<|tool_call_end|>"
      bad_matches = Regex.scan(func_call_pattern, bad_content, capture: :all_names)
      assert length(bad_matches) == 0

      # This confirms that OpenAI-style IDs do not match the current regex pattern
    end

    test "debug - what if LLM outputs malformed Kimi K2 with OpenAI-style function name" do
      # What if the LLM somehow generates this malformed pattern?
      # Using the previous tool_call_id as the new function identifier
      content = """
      I'll help with that.

      <|tool_calls_section_begin|>
      <|tool_call_begin|>call_g984eya7rrq3zfn6ty68nh50:0<|tool_call_argument_begin|>{"messages":[{"content":"What are your capabilities?","role":"user"}]}<|tool_call_end|>
      <|tool_calls_section_end|>
      """

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      {:ok, result} = KimiK2Adapter.extract_tool_calls(message)

      # This should match the regex since it has the `:0` suffix
      # Let's see what function name gets extracted
      assert length(result.tool_calls) == 1
      [tool_call] = result.tool_calls

      # The function name extraction logic:
      # tool_call_id = "call_g984eya7rrq3zfn6ty68nh50:0"
      # String.split(".") -> ["call_g984eya7rrq3zfn6ty68nh50:0"]
      # Enum.at(1, "") -> "" (no second element after split)
      # String.split(":") on "" -> [""]
      # Enum.at(0, "") -> ""

      # So function name should be empty string, not the tool call ID
      assert tool_call.function.name == ""
      assert tool_call.id == "call_g984eya7rrq3zfn6ty68nh50:0"
    end
  end

  describe "agent integration" do
    test "Kimi K2 adapter processes messages in agent workflow" do
      # This test demonstrates that the adapter would be called automatically
      # when the agent processes messages that contain Kimi K2 tool call format

      content = """
      I'll help you with that task.

      <|tool_calls_section_begin|>
      <|tool_call_begin|>functions.calculate:0<|tool_call_argument_begin|>{"operation": "add", "a": 5, "b": 3}<|tool_call_end|>
      <|tool_calls_section_end|>
      """

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      # Simulate what the agent would do - extract tool calls using the adapter
      {:ok, processed_message} = KimiK2Adapter.extract_tool_calls(message)

      assert processed_message.role == "assistant"
      assert processed_message.content == content
      assert length(processed_message.tool_calls) == 1

      [tool_call] = processed_message.tool_calls
      assert tool_call.id == "functions.calculate:0"
      assert tool_call.function.name == "calculate"
      assert tool_call.function.arguments == ~s|{"operation": "add", "a": 5, "b": 3}|
    end

    test "Kimi K2 adapter processes multiple tool calls in single response" do
      # Test demonstrates parsing multiple tool calls from a single agent response
      content = """
      I'll help you with both tasks. Let me get the weather and then check your calendar.

      <|tool_calls_section_begin|>
      <|tool_call_begin|>functions.get_weather:0<|tool_call_argument_begin|>{"location": "San Francisco", "unit": "fahrenheit"}<|tool_call_end|>
      <|tool_call_begin|>functions.check_calendar:1<|tool_call_argument_begin|>{"date": "2025-01-20", "type": "appointments"}<|tool_call_end|>
      <|tool_call_begin|>functions.send_notification:2<|tool_call_argument_begin|>{"message": "Tasks completed", "priority": "low"}<|tool_call_end|>
      <|tool_calls_section_end|>
      """

      message = %Message{role: "assistant", content: content, tool_calls: nil}

      # Simulate agent processing with KimiK2Adapter
      {:ok, processed_message} = KimiK2Adapter.extract_tool_calls(message)

      assert processed_message.role == "assistant"
      assert processed_message.content == content
      assert length(processed_message.tool_calls) == 3

      [weather_call, calendar_call, notification_call] = processed_message.tool_calls

      # Verify first tool call
      assert weather_call.id == "functions.get_weather:0"
      assert weather_call.function.name == "get_weather"
      assert weather_call.function.arguments == ~s|{"location": "San Francisco", "unit": "fahrenheit"}|

      # Verify second tool call
      assert calendar_call.id == "functions.check_calendar:1"
      assert calendar_call.function.name == "check_calendar"
      assert calendar_call.function.arguments == ~s|{"date": "2025-01-20", "type": "appointments"}|

      # Verify third tool call
      assert notification_call.id == "functions.send_notification:2"
      assert notification_call.function.name == "send_notification"
      assert notification_call.function.arguments == ~s|{"message": "Tasks completed", "priority": "low"}|
    end
  end
end
