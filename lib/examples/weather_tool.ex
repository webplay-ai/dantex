defmodule Dantex.Examples.WeatherTool do
  @moduledoc """
  Example tool that demonstrates the use of Ecto schemas for input and output validation.
  """
  use Dantex.Tool.Basic

  @tool_name "get_weather"
  @tool_description "Get the weather forecast for a location"
  @input_schema Dantex.Examples.WeatherInputSchema
  @output_schema Dantex.Examples.WeatherOutputSchema

  def do_call(params) do
    # In a real implementation, this would call a weather API
    # For this example, we'll just return mock data
    forecast =
      for day <- 1..params.days do
        %{
          day: day,
          temp: 20.0 + (day * 0.5), # Deterministic value based on day
          conditions: Enum.at(["Sunny", "Cloudy", "Rainy"], rem(day - 1, 3)) # Deterministic selection
        }
      end

    result = %{
      location: params.location,
      current_temp: 22.5,
      conditions: "Sunny",
      forecast: forecast
    }

    {:ok, result}
  end

end
