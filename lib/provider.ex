defmodule Dantex.Provider do
  alias Dantex.Message
  @type message :: Message.t()
  @type completion_options :: [
          model: String.t(),
          temperature: float(),
          max_tokens: integer()
        ]

  @type reason :: term()
  @type t :: module()

  @type usage :: %{
          total_tokens: integer()
        }

  @callback chat_completion(String.t(), list(Message.t())) ::
              {:ok, list(Message.t()), usage()} | {:error, term()}
end
