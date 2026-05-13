defmodule LeanLspTest do
  use ExUnit.Case
  doctest LeanLsp

  test "greets the world" do
    assert LeanLsp.hello() == :world
  end
end
