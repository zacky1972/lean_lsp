defmodule LeanLsp.PackageContentsTest do
  use ExUnit.Case, async: true

  @required_package_files [
    ".formatter.exs",
    "CHANGELOG.md",
    "LICENSE.md",
    "README.md",
    "docs",
    "lib",
    "mix.exs"
  ]

  @excluded_package_entries [
    "_build",
    "deps",
    "doc",
    "tmp",
    "cover",
    ".elixir_ls",
    "priv",
    "priv/plts",
    "test",
    "scripts"
  ]

  test "package files explicitly include release files and documentation extras" do
    files = package_files()

    for path <- @required_package_files do
      assert path in files
    end

    refute Enum.any?(files, &String.starts_with?(&1, "README*"))
    refute Enum.any?(files, &String.starts_with?(&1, "LICENSE*"))
    refute Enum.any?(files, &String.starts_with?(&1, "CHANGELOG*"))
  end

  test "package files exclude local build outputs and CI-only artifacts" do
    files = package_files()

    for path <- @excluded_package_entries do
      refute path in files
    end
  end

  test "docs extras exist and are covered by package files" do
    files = package_files()
    extras = docs_extras()

    assert "README.md" in extras
    assert "docs/module-responsibilities.md" in extras
    assert "docs/hex-package-contents.md" in extras

    for path <- extras do
      assert File.exists?(path), "expected docs extra #{path} to exist"

      assert covered_by_package_files?(path, files),
             "expected #{path} to be included by package[:files]"
    end
  end

  test "package contents alias builds and verifies the unpacked package" do
    aliases = LeanLsp.MixProject.project() |> Keyword.fetch!(:aliases)
    alias_steps = Keyword.fetch!(aliases, :"package.contents")

    assert alias_steps == ["cmd sh scripts/check_hex_package_contents.sh"]
  end

  defp package_files do
    LeanLsp.MixProject.project()
    |> Keyword.fetch!(:package)
    |> Keyword.fetch!(:files)
    |> Enum.map(&to_string/1)
  end

  defp docs_extras do
    LeanLsp.MixProject.project()
    |> Keyword.fetch!(:docs)
    |> Keyword.fetch!(:extras)
    |> Enum.map(&to_string/1)
  end

  defp covered_by_package_files?(path, package_files) do
    Enum.any?(package_files, fn
      ^path ->
        true

      package_path ->
        directory_cover?(path, package_path)
    end)
  end

  defp directory_cover?(path, package_path) do
    File.dir?(package_path) and String.starts_with?(path, package_path <> "/")
  end
end
