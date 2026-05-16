defmodule LeanLsp.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/zacky1972/lean_lsp"
  @hexdocs_url "https://hexdocs.pm/lean_lsp"

  def project do
    [
      app: :lean_lsp,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      name: "LeanLsp",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      elixirc_paths: elixirc(Mix.env()),
      test_ignore_filters: ["test/support/fake_runtime.ex"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def docs do
    [
      main: "readme",
      source_ref: "main",
      extras: docs_extras(),
      groups_for_modules: [
        "Public entry point": [LeanLsp],
        "Runtime preview": [
          LeanLsp.Runtime,
          LeanLsp.Runtime.Config,
          LeanLsp.Runtime.Docker
        ]
      ],
      groups_for_extras: [
        "Getting started": ["README.md"],
        "Release readiness": [
          "CHANGELOG.md",
          "docs/hex-package-metadata.md",
          "docs/release-scope-and-stability.md",
          "docs/module-responsibilities.md",
          "docs/runtime-dependency-and-docker-policy.md"
        ],
        Legal: ["LICENSE.md"]
      ]
    ]
  end

  def package do
    [
      name: "lean_lsp",
      licenses: ["Apache-2.0"],
      files: package_files(),
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "GitHub" => @source_url,
        "HexDocs" => @hexdocs_url
      }
    ]
  end

  defp package_files do
    [
      ".formatter.exs",
      "CHANGELOG.md",
      "LICENSE.md",
      "README.md",
      "docs",
      "lib",
      "mix.exs"
    ]
  end

  def aliases do
    [
      "package.contents": [
        "cmd sh scripts/check_hex_package_contents.sh"
      ],
      check: [
        "hex.audit",
        "compile --warnings-as-errors --force",
        "format --check-formatted",
        "credo",
        "deps.unlock --check-unused",
        "spellweaver.check",
        "dialyzer"
      ],
      "publish.check": [
        "cmd rm -rf _build/hex_publish_check",
        "cmd mix hex.build --unpack --output _build/hex_publish_check",
        "cmd mix docs --warnings-as-errors",
        "cmd mix hex.publish --dry-run --yes"
      ],
      precommit: [
        "hex.audit",
        "compile --warnings-as-errors --force",
        "format",
        "credo",
        "deps.unlock --unused",
        "spellweaver.check",
        "dialyzer",
        "test"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  def dialyzer do
    [
      plt_add_apps: [:mix],
      plt_file: {:no_warn, "priv/plts/project.plt"},
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp description do
    "Experimental Lean LSP foundation and Docker runtime preview for Elixir; full LSP client support is roadmap work."
  end

  defp docs_extras do
    [
      "README.md",
      "CHANGELOG.md",
      "LICENSE.md",
      "docs/hex-package-metadata.md",
      "docs/release-scope-and-stability.md",
      "docs/module-responsibilities.md",
      "docs/hex-package-contents.md"
    ]
    |> Enum.uniq()
    |> Enum.filter(&File.exists?/1)
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:docker_availability, "~> 1.0"},
      {:nstandard, "~> 0.3"},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:spellweaver, "~> 0.1", only: [:dev, :test], runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp elixirc(:test), do: ["lib", "test/support"]
  defp elixirc(_), do: ["lib"]
end
