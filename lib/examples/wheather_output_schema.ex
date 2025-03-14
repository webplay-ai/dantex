defmodule Dantex.Examples.WeatherOutputSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :location, :string
    field :current_temp, :float
    field :conditions, :string
    field :forecast, {:array, :map}
  end

  def changeset(struct, params) do
    fields = __schema__(:fields)

    struct
    |> cast(params, fields)
    |> validate_required(fields)
  end
end
