defmodule Dantex.Tool.ToolAdapter do
  @moduledoc """
  Behaviour for tool adapters that extract tool calls from different message formats.
  
  Tool adapters handle the parsing and extraction of function calls from provider-specific
  response formats, converting them to a standardized tool call structure.
  """
  alias Dantex.Message

  @type t :: module()

  @callback extract_tool_calls(Message.t()) :: {:ok, Message.t()} | {:error, term()}

end
