defmodule LeanLsp.PublishCheckAliasTest do
  use ExUnit.Case, async: true

  @alias_name :"publish.check"

  test "defines a non-interactive safe Hex pre-publish validation alias" do
    aliases = Mix.Project.config() |> Keyword.fetch!(:aliases)

    assert Keyword.has_key?(aliases, @alias_name)

    commands = Keyword.fetch!(aliases, @alias_name)

    assert command_present?(commands, "cmd mix hex.build --unpack")
    assert command_present?(commands, "--output _build/hex_publish_check")
    assert command_present?(commands, "cmd mix docs --warnings-as-errors")
    assert command_present?(commands, "cmd mix hex.publish --dry-run --yes")

    refute unsafe_yes_publish_command?(commands)
  end

  test "package files exclude generated Dialyzer PLTs" do
    package = Mix.Project.config() |> Keyword.fetch!(:package)
    files = Keyword.fetch!(package, :files)

    assert "lib" in files
    assert "docs" in files
    refute "priv" in files
    refute Enum.any?(files, &String.contains?(&1, "priv/plts"))
  end

  defp command_present?(commands, fragment) do
    Enum.any?(commands, fn
      command when is_binary(command) -> String.contains?(command, fragment)
      _other -> false
    end)
  end

  defp unsafe_yes_publish_command?(commands) do
    Enum.any?(commands, fn
      command when is_binary(command) ->
        String.contains?(command, "hex.publish") and
          String.contains?(command, "--yes") and
          not String.contains?(command, "--dry-run")

      _other ->
        false
    end)
  end
end
