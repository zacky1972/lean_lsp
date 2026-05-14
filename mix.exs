defmodule LeanLsp.MixProject do
  use Mix.Project

  def project do
    [
      app: :lean_lsp,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "an OTP-native Elixir client for running and querying Lean's language server, with Docker-backed runtime support.",
      name: "Lean lsp",
      docs: docs(),
      package: package(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      elixirc_paths: elixirc(Mix.env())
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
      extras: ["README.md"]
    ]
  end

  def package do
    [
      name: :lean_lsp,
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/zacky1972/lean_lsp"}
    ]
  end

  def aliases do
    [
      check: [
        "hex.audit",
        "compile --warnings-as-errors --force",
        "format --check-formatted",
        "credo",
        "deps.unlock --check-unused",
        "spellweaver.check",
        "dialyzer"
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
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
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
