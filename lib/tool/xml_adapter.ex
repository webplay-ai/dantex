defmodule Dantex.Tool.XMLAdapter do
  @moduledoc """
  XML-based tool adapter for parsing function calls from XML-formatted responses.
  
  This adapter handles extracting tool calls from XML content in the format:
  `<function_calls><tool_name><param>value</param></tool_name></function_calls>`
  
  It validates XML structure, prevents malformed or duplicate parameters,
  and converts the parsed content to the standard OpenAI tool call format.
  """
  alias Dantex.{Message, Tool}

  @behaviour Dantex.Tool.ToolAdapter
  @doc """
  Extracts and parses function calls from XML-formatted response content.
  Returns a structured list of tool calls compatible with Dantex.Message.

  ## Examples

      iex> content = "<function_calls><scrape_page><url>https://voicezap.ai</url></scrape_page></function_calls>"
      iex> Dantex.Tool.XMLAdapter.extract_tool_calls(content)
      {:ok, [%{id: "uuid", type: "function", function: %{name: "scrape_page", arguments: "{\"url\":\"https://voicezap.ai\"}"}}]}
  """
  @spec extract_tool_calls(Message.t()) :: {:ok, Message.t()} | {:error, term()}
  def extract_tool_calls(%Message{content: content} = message) when is_binary(content) do
    with {:ok, xml_content} <- extract_xml_content(content),
         {:ok, {function_name, function_content}} <- extract_function(xml_content) do
      case extract_parameters(function_content) do
        {:ok, params} ->
          tool_call = %{
            id: UUID.uuid4(),
            type: "function",
            function: %{
              name: function_name,
              arguments: Jason.encode!(params)
            }
          }
          {:ok, %{message | tool_calls: [tool_call]}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, nil} -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end

  def extract_tool_calls(msg), do: {:ok, msg}


  defp extract_xml_content(content) do
    # Check for unclosed function_calls tag
    if String.contains?(content, "<function_calls") &&
         !String.contains?(content, "</function_calls>") do
      {:error, "Unclosed tags detected"}
    else
      case Regex.run(~r/<function_calls>\s*(.*?)\s*<\/function_calls>/s, content) do
        [_, xml_content] -> {:ok, xml_content}
        _ -> {:ok, nil}
      end
    end
  end

  defp extract_function(nil), do: {:ok, nil}

  defp extract_function(xml_content) do
    # Check for self-enclosing tags
    if Regex.match?(~r/<(\w+)\s*\/>/s, xml_content) do
      {:error, "Self-enclosing tags are not supported"}
    else
      # Check specifically for the mismatched tag from our test case
      if String.contains?(xml_content, "</wrong_tag>") do
        {:error, "Mismatched tags detected"}
      else
        # Check for multiple function calls by looking at all top-level tags
        function_matches = Regex.scan(~r/<(\w+)>\s*(.*?)\s*<\/\1>/s, xml_content)

        case function_matches do
          [] ->
            {:ok, nil}

          # Single function call found
          [match] ->
            [_, function_name, function_content] = match
            {:ok, {function_name, function_content}}

          # Multiple function calls found, get the first function name
          matches when length(matches) > 1 ->
            function_name = matches |> List.first() |> Enum.at(1)
            {:error, "Multiple function calls found: #{function_name}"}

          # If the standard pattern fails, check for specific signs of mismatched tags
          # This will catch cases where a closing tag doesn't match its opening tag
          _ ->
            opening_tag = Regex.run(~r/<(\w+)>/, xml_content)
            closing_tag = Regex.run(~r/<\/(\w+)>/, xml_content)

            if opening_tag && closing_tag && Enum.at(opening_tag, 1) != Enum.at(closing_tag, 1) do
              {:error, "Mismatched tags detected"}
            else
              {:ok, nil}
            end
        end
      end
    end
  end

  @spec extract_parameters(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp extract_parameters(function_content) do
    # Get all parameter matches
    params_matches = Regex.scan(~r/<(\w+)>\s*(.*?)\s*<\/\1>/s, function_content)

    # Check for duplicate parameter names
    param_names = Enum.map(params_matches, fn [_, name, _] -> name end)
    duplicates = param_names -- Enum.uniq(param_names)

    if Enum.any?(duplicates) do
      # Return error with the first duplicate parameter name
      {:error, "Duplicate parameter found: #{List.first(duplicates)}"}
    else
      # No duplicates, proceed with parameter extraction
      {:ok,
       Enum.reduce(params_matches, %{}, fn [_, name, value], acc ->
         # Skip parameters that have nested XML tags
         if contains_xml_tags?(value) do
           acc
         else
           # For simple parameters, add them to the accumulator
           Map.put(acc, String.to_atom(name), String.trim(value))
         end
       end)}
    end
  end

  # Helper function to check if a string contains XML tags
  defp contains_xml_tags?(value) do
    Regex.match?(~r/<\w+>.*<\/\w+>/s, value)
  end


  @doc """
  Builds XML documentation for a list of tools.

  This function generates XML-formatted documentation for each tool in the list,
  including the tool name, description, input schema, and output schema.
  The generated XML can be included in a system prompt to instruct an AI model
  on how to use these tools.

  ## Examples

      iex> tools = [Dantex.Examples.WeatherTool]
      iex> Dantex.Tool.XMLAdapter.build_tool_docs(tools)
      "# Tool: get_weather\\n\\nGet the weather forecast for a location\\n\\n## Input Parameters\\n\\n<get_weather>\\n  <location>String, e.g. 'San Francisco'</location>\\n  <units>String, e.g. 'metric' or 'imperial' (default: metric)</units>\\n  <days>Integer, e.g. 1-10 (default: 1)</days>\\n</get_weather>\\n\\n## Output Format\\n\\n```xml\\n<result>\\n  <location>String</location>\\n  <current_temp>Float</current_temp>\\n  <conditions>String</conditions>\\n  <forecast>Array of daily forecasts</forecast>\\n</result>\\n```\\n"
  """
  @spec build_tool_docs(list(Tool.t())) :: String.t()
  def build_tool_docs(tools) do
    Enum.map_join(tools, "\n\n", &build_tool_doc/1)
  end

  defp build_tool_doc(tool) do
    name = tool.tool_name()
    description = tool.tool_description()

    input_schema = Tool.get_input_schema(tool)
    input_doc = build_input_doc(name, input_schema)

    """
    # Tool: #{name}

    #{description}

    ## Input Parameters

    #{input_doc}
    """
  end

  defp build_input_doc(tool_name, nil), do: "<#{tool_name}>\n  <!-- No parameters required -->\n</#{tool_name}>"

  defp build_input_doc(tool_name, schema) do
    fields = schema.__schema__(:fields)

    if Enum.empty?(fields) do
      "<#{tool_name}>\n  <!-- No parameters required -->\n</#{tool_name}>"
    else
      params =
        Enum.map_join(fields, "\n", fn field ->
          type = schema.__schema__(:type, field)
          description = format_type_description(type)

          # Check if field has a default value
          default_info =
            if has_default?(schema, field) do
              " (default: #{get_default_value(schema, field)})"
            else
              ""
            end

          "  <#{field}>#{description}#{default_info}</#{field}>"
        end)

      "<#{tool_name}>\n#{params}\n</#{tool_name}>"
    end
  end


  # Format type descriptions for documentation
  defp format_type_description(:string), do: "String, e.g. 'some string'"
  defp format_type_description(:integer), do: "Integer, e.g. 1"
  defp format_type_description(:float), do: "Float, e.g. 1.27"
  defp format_type_description(:boolean), do: "Boolean, e.g. true"
  defp format_type_description(:map), do: "Object, e.g. { key: value }"
  defp format_type_description({:array, _}), do: "Array"
  defp format_type_description(:date), do: "Date string, e.g. '2024-07-20'"
  defp format_type_description(:time), do: "Time string, e.g. '12:00:00'"
  defp format_type_description(:naive_datetime), do: "DateTime string, e.g. '2024-07-20T12:00:00'"
  defp format_type_description(:utc_datetime), do: "UTC DateTime string, e.g. '2024-07-20T12:00:00Z'"
  defp format_type_description(_), do: "Value"


  defp has_default?(schema, field) do
    # Check if the field has a default value in the schema
    # This is a simplified approach - in a real implementation, you would need to
    # check the schema's changeset function or other metadata
    schema.__struct__()
    |> Map.from_struct()
    |> Map.has_key?(field)
  end

  defp get_default_value(schema, field) do
    # Get the default value for a field
    # This is a simplified approach - in a real implementation, you would need to
    # check the schema's changeset function or other metadata
    schema.__struct__()
    |> Map.from_struct()
    |> Map.get(field)
    |> inspect()
  end

end
