defmodule CalculatorInputSchema do
  @moduledoc """
  Input schema for calculator operations.
  
  Defines the expected input structure for basic mathematical operations
  including operation type and operand values.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :operation, :string
    field :a, :float
    field :b, :float
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:operation, :a, :b])
    |> validate_required([:operation, :a, :b])
    |> validate_inclusion(:operation, ["add", "subtract", "multiply", "divide"])
  end
end


defmodule Dantex.Examples.CalculatorTool do
  @moduledoc """
  Example tool using the new DSL syntax that performs basic mathematical operations.
  Demonstrates input validation, context access, and structured output.
  """
  use Dantex.Tool

  tool :calculate,
    description: "Perform basic mathematical operations (add, subtract, multiply, divide)",
    input: CalculatorInputSchema do

    # Access context if needed - could contain user preferences, settings, etc.
    precision = Map.get(context, :precision, 2)
    
    # Perform the calculation
    result = case params.operation do
      "add" -> params.a + params.b
      "subtract" -> params.a - params.b
      "multiply" -> params.a * params.b
      "divide" -> 
        if params.b == 0.0 do
          raise "Division by zero is not allowed"
        else
          params.a / params.b
        end
    end

    # Format the result according to precision from context
    formatted_result = Float.round(result, precision)
    expression = "#{params.a} #{get_operator(params.operation)} #{params.b}"

    # Return structured output
    %{
      result: formatted_result,
      operation: params.operation,
      expression: expression
    }
  end

  # Helper function to convert operation to mathematical operator
  defp get_operator("add"), do: "+"
  defp get_operator("subtract"), do: "-"
  defp get_operator("multiply"), do: "*"
  defp get_operator("divide"), do: "/"
end