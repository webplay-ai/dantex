defmodule DantexTest do
  use ExUnit.Case

  # We'll test the Tool module instead of the non-existent Dantex module
  test "tool module exists" do
    assert Code.ensure_loaded?(Dantex.Tool)
  end

  test "tool schema helpers module exists" do
    assert Code.ensure_loaded?(Dantex.Tool.SchemaHelpers)
  end
end
