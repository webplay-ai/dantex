defmodule Dantex.Examples.WeatherInputSchema do
  @moduledoc """
  Input schema for weather tool demonstration.
  
  Defines the expected input structure for weather queries including location,
  units (metric/imperial), and number of forecast days.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :location, :string
    field :units, :string, default: "metric"
    field :days, :integer, default: 1
  end

  def changeset(struct, params) do
    fields = __schema__(:fields)

    struct
    |> cast(params, fields)
    |> validate_required([:location])
    |> validate_length(:location, min: 1, message: "Location cannot be empty")
    |> validate_inclusion(:units, ["metric", "imperial"], message: "Units must be either 'metric' or 'imperial'")
    |> validate_number(:days, greater_than: 0, less_than_or_equal_to: 10, message: "Days must be between 1 and 10")
  end
end
