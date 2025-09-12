defmodule Dantex.Examples.SimpleWeatherTool do
  @moduledoc """
  Example tool using inline schema definitions instead of external Ecto schemas.
  """
  use Dantex.Tool

  tool :get_weather,
    description: "Get weather information",
    input: [
      location: [:string, required: true, min_length: 1],
      units: [:string, default: "celsius", enum: ["celsius", "fahrenheit"]],
      days: [:integer, default: 1, min: 1, max: 7]
    ],
    output: [
      location: :string,
      units: :string,
      forecast: {:array, :map},
      api_used: :string
    ] do

    # Access context 
    api_key = context[:weather_api_key] || "demo_key"
    
    # Mock weather data based on parameters
    forecast = case params.days do
      1 -> 
        [%{day: 1, temp: 22.5, conditions: "Sunny"}]
      days when days > 1 ->
        for day <- 1..days do
          %{
            day: day,
            temp: 20.0 + (day * 0.5),
            conditions: Enum.at(["Sunny", "Cloudy", "Rainy"], rem(day - 1, 3))
          }
        end
    end
    
    # Convert temperature based on units
    converted_forecast = if params.units == "fahrenheit" do
      Enum.map(forecast, fn day ->
        %{day | temp: day.temp * 9/5 + 32}
      end)
    else
      forecast
    end
    
    %{
      location: params.location,
      units: params.units,
      forecast: converted_forecast,
      api_used: api_key
    }
  end
end