defmodule Dantex.Tool.XMLAdapterTest do
  use ExUnit.Case

  alias Dantex.Tool.XMLAdapter

  describe "extract_function_calls/1" do
    test "successfully extracts a simple function call" do
      content = "<function_calls><scrape_page><url>https://voicezap.ai</url></scrape_page></function_calls>"

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      assert tool_call.type == "function"
      assert tool_call.function.name == "scrape_page"
      assert tool_call.function.arguments == ~s({"url":"https://voicezap.ai"})
    end

    test "successfully extracts a function call with multiple parameters" do
      content = """
      <function_calls>
        <search_products>
          <query>smartphone</query>
          <max_results>10</max_results>
          <sort_by>price</sort_by>
        </search_products>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      assert tool_call.type == "function"
      assert tool_call.function.name == "search_products"

      arguments = Jason.decode!(tool_call.function.arguments)
      assert arguments["query"] == "smartphone"
      assert arguments["max_results"] == "10"
      assert arguments["sort_by"] == "price"
    end

    test "returns {:ok, nil} for nil input" do
      assert {:ok, nil} = XMLAdapter.extract_function_calls(nil)
    end

    test "returns {:ok, nil} for empty input" do
      assert {:ok, nil} = XMLAdapter.extract_function_calls("")
    end

    test "returns {:ok, nil} when no function calls are found" do
      content = "<function_calls></function_calls>"
      assert {:ok, nil} = XMLAdapter.extract_function_calls(content)
    end

    test "returns error for unclosed tags" do
      content = "<function_calls><get_weather><location>London</location></get_weather>"
      assert {:error, "Unclosed tags detected"} = XMLAdapter.extract_function_calls(content)
    end

    test "returns error for mismatched tags" do
      content = "<function_calls><get_weather><location>London</location></wrong_tag></function_calls>"
      assert {:error, "Mismatched tags detected"} = XMLAdapter.extract_function_calls(content)
    end

    test "returns error for self-enclosing tags" do
      content = "<function_calls><get_weather/></function_calls>"
      assert {:error, "Self-enclosing tags are not supported"} = XMLAdapter.extract_function_calls(content)
    end

    test "returns error for multiple function calls" do
      content = """
      <function_calls>
        <get_weather><location>London</location></get_weather>
        <get_news><category>tech</category></get_news>
      </function_calls>
      """

      assert {:error, message} = XMLAdapter.extract_function_calls(content)
      assert String.contains?(message, "Multiple function calls found")
    end

    test "returns error for duplicate parameters" do
      content = """
      <function_calls>
        <get_weather>
          <location>London</location>
          <location>Paris</location>
        </get_weather>
      </function_calls>
      """

      assert {:error, "Duplicate parameter found: location"} = XMLAdapter.extract_function_calls(content)
    end

    test "skips parameters with nested XML tags" do
      content = """
      <function_calls>
        <complex_function>
          <simple_param>value</simple_param>
          <complex_param><nested>nested value</nested></complex_param>
        </complex_function>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)

      # Only the simple parameter should be included
      assert Map.has_key?(arguments, "simple_param")
      refute Map.has_key?(arguments, "complex_param")
    end

    # New test cases adapted from WebplayEx.Agents.WebplayTest

    test "handles whitespace in XML content" do
      content = """
      <function_calls>
        <scrape_page>
          <url>
            https://voicezap.ai
          </url>
        </scrape_page>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)
      assert arguments["url"] == "https://voicezap.ai"
    end

    test "handles special characters in parameters" do
      content = """
      <function_calls>
        <scrape_page>
          <url>https://example.com/page?param=value&amp;other=123</url>
          <selector>#item > div.class[data-attr="value"]</selector>
        </scrape_page>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)
      assert arguments["url"] == "https://example.com/page?param=value&amp;other=123"
      assert arguments["selector"] == "#item > div.class[data-attr=\"value\"]"
    end

    test "extracts function calls with text before and after" do
      content = """
      Some text before the function calls
      <function_calls>
        <scrape_page>
          <url>https://voicezap.ai</url>
        </scrape_page>
      </function_calls>
      Some text after the function calls
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)
      assert arguments["url"] == "https://voicezap.ai"
    end

    test "handles HTML entities in parameters" do
      content = """
      <function_calls>
        <scrape_page>
          <url>https://example.com/page?q=search&amp;lang=en</url>
          <selector>div.item > span.title</selector>
        </scrape_page>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)
      assert arguments["url"] == "https://example.com/page?q=search&amp;lang=en"
      assert arguments["selector"] == "div.item > span.title"
    end

    test "handles Unicode characters in parameters" do
      content = """
      <function_calls>
        <scrape_page>
          <url>https://example.com/café</url>
          <selector>.résumé</selector>
          <text>こんにちは世界</text>
        </scrape_page>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)
      assert arguments["url"] == "https://example.com/café"
      assert arguments["selector"] == ".résumé"
      assert arguments["text"] == "こんにちは世界"
    end

    test "handles CDATA sections in parameters" do
      content = """
      <function_calls>
        <scrape_page>
          <url>https://example.com</url>
          <selector><![CDATA[div.item > span[data-attr="complex<value>"]]]></selector>
        </scrape_page>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)
      assert arguments["url"] == "https://example.com"
      assert arguments["selector"] == "<![CDATA[div.item > span[data-attr=\"complex<value>\"]]]>"
    end

    test "handles XML with comments" do
      content = """
      <function_calls>
        <!-- This is a comment -->
        <scrape_page>
          <url>https://example.com</url>
          <!-- Another comment -->
          <selector>.content</selector>
        </scrape_page>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)
      assert arguments["url"] == "https://example.com"
      assert arguments["selector"] == ".content"
    end

    test "handles extremely long parameter values" do
      long_path = String.duplicate("very-long-path-segment-", 100)
      content = """
      <function_calls>
        <scrape_page>
          <url>https://example.com/#{long_path}</url>
        </scrape_page>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)
      assert String.starts_with?(arguments["url"], "https://example.com/")
      assert String.length(arguments["url"]) > 1000
    end

    test "returns error for XML with duplicate function calls in content" do
      content = """
      <function_calls>
        <scrape_page>
          <url>https://example.com/</url>
        </scrape_page>
        <scrape_page>
          <url>https://foobar.com/</url>
        </scrape_page>
      </function_calls>
      """

      assert {:error, message} = XMLAdapter.extract_function_calls(content)
      assert String.contains?(message, "Multiple function calls found: scrape_page")
    end
  end

  describe "extract_parameters/1 (via extract_function_calls)" do
    test "handles whitespace in parameter values" do
      content = """
      <function_calls>
        <search>
          <query>  search term with spaces  </query>
        </search>
      </function_calls>
      """

      assert {:ok, [tool_call]} = XMLAdapter.extract_function_calls(content)
      arguments = Jason.decode!(tool_call.function.arguments)

      # The whitespace should be trimmed
      assert arguments["query"] == "search term with spaces"
    end
  end
end
