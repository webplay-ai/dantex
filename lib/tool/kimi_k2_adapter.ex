defmodule Dantex.Tool.KimiK2Adapter do
  @moduledoc """
  Tool adapter for parsing Kimi K2 (Together AI) manual tool call format.

  This adapter handles the special Together AI tool call format used by Kimi K2 models:
  <|tool_calls_section_begin|>
  <|tool_call_begin|>function_id:0<|tool_call_argument_begin|>{"arg": "value"}<|tool_call_end|>
  <|tool_calls_section_end|>
  """

  @behaviour Dantex.Tool.ToolAdapter

  alias Dantex.Message

  @impl true
  def extract_tool_calls(%Message{content: content} = message) when is_binary(content) do
    tool_calls = parse_tool_calls_from_content(content)

    updated_message = %{message | tool_calls: tool_calls}
    {:ok, updated_message}
  end

  @impl true
  def extract_tool_calls(%Message{} = message) do
    {:ok, message}
  end

  defp parse_tool_calls_from_content(content) do
    if String.contains?(content, "<|tool_calls_section_begin|>") do
      case Regex.run(~r/<\|tool_calls_section_begin\|>(.*?)<\|tool_calls_section_end\|>/s, content) do
        [_, tool_calls_section] ->
          parse_tool_calls_section(tool_calls_section)

        nil ->
          []
      end
    else
      []
    end
  end

  defp parse_tool_calls_section(tool_calls_section) do
    func_call_pattern = ~r/<\|tool_call_begin\|>\s*(?<tool_call_id>[\w\.]+:\d+)\s*<\|tool_call_argument_begin\|>\s*(?<function_arguments>.*?)\s*<\|tool_call_end\|>/s

    Regex.scan(func_call_pattern, tool_calls_section, capture: :all_names)
    |> Enum.map(fn captures ->
      # When using capture: :all_names, named captures are returned in alphabetical order
      {tool_call_id, function_args} =
        case captures do
          [function_args, tool_call_id] -> {tool_call_id, function_args}  # Named captures are in alphabetical order
          %{"tool_call_id" => tool_call_id, "function_arguments" => function_args} -> {tool_call_id, function_args}
          _ -> {"", ""}
        end

      # Parse function_id: functions.get_weather:0
      function_name =
        tool_call_id
        |> String.split(".")
        |> Enum.at(1, "")
        |> String.split(":")
        |> Enum.at(0, "")

      %{
        id: tool_call_id,
        type: "function",
        function: %{
          name: function_name,
          arguments: String.trim(function_args)
        }
      }
    end)
  end
end
