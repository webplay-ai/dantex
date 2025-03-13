defmodule Dantex.Provider do
  alias Dantex.Message
  alias Dantex.Tool

  @type message :: Message.t()
  @type t :: module()

  @type usage :: %{
          total_tokens: integer()
        }

  @callback chat_completion(String.t(), list(Message.t()), list(Tool.t())) ::
              {:ok, list(Message.t()), usage()} | {:error, term()}
end
