defmodule LeanLsp.DownstreamSmokeAliasTest do
  use ExUnit.Case, async: true

  @script "scripts/downstream_smoke_test.sh"
  @doc "docs/downstream-smoke-test.md"

  test "downstream smoke alias is available" do
    aliases = aliases()

    assert Keyword.fetch!(aliases, :"downstream.smoke") == [
             "cmd sh scripts/downstream_smoke_test.sh"
           ]
  end

  test "publish.check includes downstream smoke before dry-run publish" do
    steps = aliases() |> Keyword.fetch!(:"publish.check")

    assert "cmd sh scripts/downstream_smoke_test.sh" in steps
    assert "cmd mix hex.publish --dry-run --yes" in steps

    smoke_index = Enum.find_index(steps, &(&1 == "cmd sh scripts/downstream_smoke_test.sh"))
    publish_index = Enum.find_index(steps, &(&1 == "cmd mix hex.publish --dry-run --yes"))

    assert smoke_index < publish_index
  end

  test "downstream smoke documentation is included in HexDocs extras" do
    docs = LeanLsp.MixProject.project() |> Keyword.fetch!(:docs)
    extras = Keyword.fetch!(docs, :extras)

    assert @doc in extras
  end

  test "downstream smoke script creates a temporary project and calls public API" do
    script = File.read!(@script)

    assert script =~ "mix new"
    assert script =~ "LEAN_LSP_DOWNSTREAM_DEP"
    assert script =~ "LEAN_LSP_DOWNSTREAM_ROOT"
    assert script =~ "{:lean_lsp, path:"
    assert script =~ "{:lean_lsp, requirement}"
    assert script =~ "mix compile --warnings-as-errors"
    assert script =~ "LeanLsp.runtime_config([])"
  end

  test "downstream smoke script treats Docker as optional" do
    script = File.read!(@script)

    assert script =~ "LEAN_LSP_DOWNSTREAM_DOCKER"
    assert script =~ "Docker unavailable; skipping optional Docker runtime smoke check"
    assert script =~ "LeanLsp.start_runtime([])"
    assert script =~ "LeanLsp.Runtime.Docker.stop(runtime)"
  end

  test "downstream smoke procedure covers local, Hex, and Docker modes" do
    doc = File.read!(@doc)

    assert doc =~ "mix downstream.smoke"
    assert doc =~ "path:"
    assert doc =~ "LEAN_LSP_DOWNSTREAM_DEP=hex"
    assert doc =~ "LEAN_LSP_DOWNSTREAM_DOCKER=auto"
    assert doc =~ "LEAN_LSP_DOWNSTREAM_DOCKER=skip"
    assert doc =~ "LEAN_LSP_DOWNSTREAM_DOCKER=required"
    assert doc =~ "LeanLsp.runtime_config/1"
  end

  defp aliases do
    LeanLsp.MixProject.project()
    |> Keyword.fetch!(:aliases)
  end
end
