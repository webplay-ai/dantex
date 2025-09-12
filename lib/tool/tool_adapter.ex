defmodule Dantex.Tool.ToolAdapter do
  alias Dantex.Message

  @type t :: module()

  @callback extract_tool_calls(Message.t()) :: {:ok, Message.t()} | {:error, term()}

end
