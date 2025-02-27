defmodule Dantex.Logging do
  @moduledoc """
  A flexible logging interface that supports multiple logging backends.
  This module provides a consistent way to log messages while allowing
  different logging implementations to be plugged in.
  """

  require Logger

  @doc """
  Defines the behavior that any logging adapter must implement.
  This keeps the interface consistent while allowing different implementations.
  """
  defmodule Adapter do
    @callback log(
                level :: :debug | :info | :warn | :error,
                message :: String.t(),
                metadata :: map()
              ) :: :ok
  end

  @doc """
  Default adapter using Elixir's built-in Logger.
  """
  defmodule DefaultAdapter do
    @behaviour Dantex.Logging.Adapter

    def log(level, message, metadata) do
      Logger.log(level, message, metadata)
    end
  end

  @doc """
  Composite logger that can send logs to multiple adapters.
  This is useful when you want to log to multiple systems simultaneously.
  """
  defmodule CompositeAdapter do
    @behaviour Dantex.Logging.Adapter

    defstruct [:adapters]

    def new(adapters) do
      %__MODULE__{adapters: adapters}
    end

    def log(level, message, metadata) do
      Enum.each(@adapters, fn adapter ->
        adapter.log(level, message, metadata)
      end)
    end
  end
end
