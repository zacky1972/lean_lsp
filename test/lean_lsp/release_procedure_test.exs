defmodule LeanLsp.ReleaseProcedureTest do
  use ExUnit.Case, async: true

  @release_doc "docs/release-procedure.md"

  test "release procedure is included in HexDocs extras and package files" do
    project = LeanLsp.MixProject.project()
    docs = Keyword.fetch!(project, :docs)
    extras = docs |> Keyword.fetch!(:extras) |> Enum.map(&to_string/1)

    files =
      project |> Keyword.fetch!(:package) |> Keyword.fetch!(:files) |> Enum.map(&to_string/1)

    assert @release_doc in extras
    assert File.exists?(@release_doc)
    assert covered_by_package_files?(@release_doc, files)
  end

  test "release procedure is linked from contributor-facing documentation" do
    metadata_doc = File.read!("docs/hex-package-metadata.md")

    assert metadata_doc =~ "Release procedure"
    assert metadata_doc =~ "release-procedure.md"
  end

  test "release procedure does not contain stale v0.1.0 release commands" do
    doc = File.read!(@release_doc)

    refute doc =~ "git tag -a v0.1.0"
    refute doc =~ "git push origin v0.1.0"
    refute doc =~ "gh release create v0.1.0"
    refute doc =~ "mix hex.publish --revert 0.1.0"
  end

  test "release procedure covers pre-publish, publish, and post-publish steps" do
    doc = File.read!(@release_doc)

    for expected <- [
          "git fetch origin main --tags",
          "git pull --ff-only origin main",
          "mix hex.user auth",
          "mix hex.user whoami",
          "mix check",
          "mix test",
          "mix docs --warnings-as-errors",
          "mix package.contents",
          "mix dependency.audit",
          "mix publish.check",
          "mix hex.publish",
          "hex.pm/packages/lean_lsp",
          "hexdocs.pm/lean_lsp",
          "LEAN_LSP_DOWNSTREAM_DEP=hex",
          "git tag -a v0.2.0",
          "git push origin v0.2.0",
          "gh release create v0.2.0",
          "mix hex.publish docs",
          "mix hex.publish --revert 0.2.0",
          "0.2.1"
        ] do
      assert doc =~ expected
    end
  end

  test "release procedure keeps final publish interactive" do
    doc = File.read!(@release_doc)

    assert doc =~ "Do not use `--yes` for the final publish command"
    assert doc =~ "--dry-run --yes"
    refute doc =~ "mix hex.publish --yes"
  end

  defp covered_by_package_files?(path, package_files) do
    Enum.any?(package_files, fn
      ^path -> true
      package_path -> File.dir?(package_path) and String.starts_with?(path, package_path <> "/")
    end)
  end
end
