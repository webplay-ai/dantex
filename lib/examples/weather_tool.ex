defmodule Dantex.Examples.WeatherTool do
  @moduledoc """
  Example tool that demonstrates the use of Ecto schemas for input validation.
  """
  use Dantex.Tool

  tool :get_weather,
    description: "Get the weather forecast for a location",
    input: Dantex.Examples.WeatherInputSchema do

    # In a real implementation, this would call a weather API
    # Access context for API keys, user preferences, etc.
    _api_key = context[:weather_api_key] || "demo_key"
    
    # For this example, we'll just return mock data
    forecast =
      for day <- 1..params.days do
        %{
          day: day,
          temp: 20.0 + (day * 0.5), # Deterministic value based on day
          conditions: Enum.at(["Sunny", "Cloudy", "Rainy"], rem(day - 1, 3)) # Deterministic selection
        }
      end

    # Return the result (no need to wrap in {:ok, result} - the DSL handles that)
    %{
      location: params.location,
      current_temp: 22.5,
      conditions: "Sunny",
      forecast: forecast
    }
  end

end
