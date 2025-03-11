defmodule Dantex.EvalHtmlHelpersTest do
  use ExUnit.Case
  alias Dantex.Eval.TestCase
  alias Dantex.Message

  # We need to expose the private functions for testing
  # This is a common pattern in Elixir for testing private functions
  defmodule TestHelpers do
    def generate_table_rows(test_cases) do
      apply(Dantex.Eval, :generate_table_rows, [test_cases])
    end

    def format_messages(messages) do
      apply(Dantex.Eval, :format_messages, [messages])
    end

    def html_escape(text) do
      apply(Dantex.Eval, :html_escape, [text])
    end
  end

  describe "HTML helper functions" do
    test "generate_table_rows/1 creates HTML rows for test cases" do
      test_cases = [
        %TestCase{
          input: [Message.user("What is 2+2?")],
          expected_output: "4",
          actual_output: "4",
          score: 1.0,
          pass: true,
          tokens: 10
        }
      ]

      # Since we can't directly test private functions, we'll check the output
      # contains expected elements
      result = TestHelpers.generate_table_rows(test_cases)

      assert result =~ "<tr>"
      assert result =~ "<td>1</td>"
      assert result =~ "What is 2+2?"
      assert result =~ "<td class=\"pass\">PASS</td>"
      assert result =~ "<td>10</td>"
    end

    test "html_escape/1 properly escapes HTML special characters" do
      text = "<script>alert(\"XSS Attack & More\")</script>"
      escaped = TestHelpers.html_escape(text)

      assert escaped == "&lt;script&gt;alert(&quot;XSS Attack &amp; More&quot;)&lt;/script&gt;"
      assert TestHelpers.html_escape(nil) == ""
      assert TestHelpers.html_escape(123) == "123"
    end

    test "format_messages/1 formats message list for display" do
      messages = [
        Message.user("Hello"),
        Message.system("System message")
      ]

      formatted = TestHelpers.format_messages(messages)

      assert formatted =~ "user: Hello"
      assert formatted =~ "system: System message"
    end
  end
end
