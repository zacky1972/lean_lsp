defmodule LeanLsp.Runtime.EnvTest do
  use ExUnit.Case, async: true

  alias LeanLsp.Runtime.Env

  describe "to_cli_args/2" do
    test "converts map environment variables to repeated CLI option arguments" do
      args = Env.to_cli_args("--env", %{"A" => "1", "B" => "2"})

      assert args
             |> Enum.chunk_every(2)
             |> Enum.sort() == [
               ["--env", "A=1"],
               ["--env", "B=2"]
             ]
    end

    test "converts list of environment variable pairs" do
      assert Env.to_cli_args("--env", [{"A", "1"}]) == ["--env", "A=1"]
    end

    test "converts keyword environment variables" do
      assert Env.to_cli_args("--env", foo: "1") == ["--env", "foo=1"]
    end

    test "keeps already formatted environment variable strings" do
      assert Env.to_cli_args("--env", ["A=1"]) == ["--env", "A=1"]
    end

    test "converts nil to an empty CLI argument list" do
      assert Env.to_cli_args("--env", nil) == []
    end
  end
end
