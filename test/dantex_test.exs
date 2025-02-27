defmodule DantexTest do
  use ExUnit.Case
  doctest Dantex

  test "greets the world" do
    assert Dantex.hello() == :world
  end
end
