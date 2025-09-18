defmodule Dantex.Provider do
  @moduledoc """
  Behaviour for AI provider implementations.
  
  Defines the interface for different AI providers (OpenAI, Gemini, Ollama) to implement
  chat completions with consistent message and tool handling across providers.
  """
  alias Dantex.Message

  @type message :: Message.t()
  @type t :: module()

  @type usage :: %{
          total_tokens: integer()
        }

  @callback chat_completion(map()) ::
              {:ok, list(Message.t()), usage()} | {:error, term()}
end
