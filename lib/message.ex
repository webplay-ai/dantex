defmodule Dantex.Message do
  @type t :: %__MODULE__{
          role: String.t(),
          content: String.t()
        }

  @derive Jason.Encoder
  defstruct [:role, :content]

  @spec system(String.t()) :: t()
  def system(message) do
    %__MODULE__{
      role: "system",
      content: message
    }
  end

  @spec user(String.t()) :: t()
  def user(message) do
    %__MODULE__{
      role: "user",
      content: message
    }
  end
end
