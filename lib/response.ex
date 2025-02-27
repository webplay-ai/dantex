defmodule Dantex.Response do
  @moduledoc """
  This module is responsible for parsing the response

  response = Response.new(model, tools, schema)

  You can, if you want to, validate the response before using it
  {:ok, valid } = response.validate("raw output from LLM")

  Convert the response to JSON, comes in handy when you uses response_format
  response.json()
  """

  alias Dantex.{Tool, Model}
  require Logger

  @type t :: %__MODULE__{
          model: Model.t(),
          tools: [Tool.t()]
        }

  defstruct [:model, :tools, :response_format]

  @spec new([
          {:model, Model.t()} | {:tools, [Tool.t()]}
        ]) ::
          t()
  def new(opts) do
    model = Keyword.fetch!(opts, :model)
    tools = Keyword.get(opts, :tools, [])

    %__MODULE__{
      model: model,
      tools: tools
    }
  end

  @doc """
  If a response_format is in form of JSON schema defintion or Ecto schema, we try to parse the response against this schema and return a map
  """
  @spec json(String.t()) :: {:ok, map()} | {:error, String.t()}
  def json(response) do
    case Jason.decode(response, keys: :atoms) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, error} ->
        Logger.error(
          "Failed to decode JSON: #{inspect(error, pretty: true)}\nContent: #{inspect(response, pretty: true)}"
        )

        {:error, "Invalid JSON response from OpenAI"}
    end
  end

  @doc """
  Get the last message as test
  """
  @spec last_message(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def last_message(response) do
    {:ok, response}
  end

  defp safe_get_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, content}
  end

  defp safe_get_content(content) do
    Logger.error("Invalid OpenAI response structure: #{inspect(content, pretty: true)}")
    {:error, "Invalid response structure from OpenAI"}
  end
end
