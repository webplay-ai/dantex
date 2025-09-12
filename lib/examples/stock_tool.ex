defmodule StockInputSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :company, :string
    field :date, :date
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:company, :date])
    |> validate_required([:company, :date])
  end
end


defmodule Dantex.Examples.StockTool do
  use Dantex.Tool

  tool :get_stock_price,
    description: "Get stock price",
    input: StockInputSchema do

    # get api key from context - or something else
    _api_key = context[:api_key]
    
    # In a real implementation, you would use the API key and make an API call
    # For now, return mock data based on the input
    
    # The tool logic - return structured data
    %{
      company: params.company,
      date: params.date,
      price: 123.45
    }
  end

end
