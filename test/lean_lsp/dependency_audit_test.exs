defmodule LeanLsp.DependencyAuditTest do
  use ExUnit.Case, async: true

  @production_dependencies [:docker_availability]
  @development_only_dependencies [:nstandard, :ex_doc, :dialyxir, :credo, :spellweaver]

  test "only intended runtime dependencies are exposed to package consumers" do
    assert production_dependency_names() == @production_dependencies
  end

  test "development tooling is limited to dev and test and is not runtime-started" do
    for app <- @development_only_dependencies do
      opts = app |> fetch_dependency!() |> dependency_options()

      assert Keyword.fetch!(opts, :only) == [:dev, :test]
      assert Keyword.fetch!(opts, :runtime) == false
    end
  end

  test "direct dependencies are Hex packages, not git, path, or umbrella deps" do
    for dep <- dependencies() do
      opts = dependency_options(dep)

      assert is_binary(dependency_requirement(dep)), inspect(dep)
      refute Keyword.has_key?(opts, :git), inspect(dep)
      refute Keyword.has_key?(opts, :github), inspect(dep)
      refute Keyword.has_key?(opts, :path), inspect(dep)
      refute Keyword.has_key?(opts, :in_umbrella), inspect(dep)
    end
  end

  test "dependency audit documentation is included in HexDocs extras" do
    docs = LeanLsp.MixProject.project() |> Keyword.fetch!(:docs)
    extras = docs |> Keyword.fetch!(:extras) |> Enum.map(&to_string/1)

    assert "docs/dependency-audit.md" in extras
    assert File.exists?("docs/dependency-audit.md")
  end

  test "dependency audit alias runs unused lock and non-interactive Hex dry-run checks" do
    aliases = LeanLsp.MixProject.project() |> Keyword.fetch!(:aliases)
    steps = Keyword.fetch!(aliases, :"dependency.audit")

    assert command_present?(steps, "deps.unlock --check-unused")
    assert command_present?(steps, "cmd mix hex.publish --dry-run --yes")
    refute unsafe_yes_publish_command?(steps)
  end

  defp production_dependency_names do
    dependencies()
    |> Enum.filter(&production_dependency?/1)
    |> Enum.map(&dependency_name/1)
  end

  defp production_dependency?(dep) do
    opts = dependency_options(dep)

    available_in_prod?(Keyword.get(opts, :only, :all)) and
      Keyword.get(opts, :runtime, true) != false
  end

  defp available_in_prod?(:all), do: true
  defp available_in_prod?(:prod), do: true
  defp available_in_prod?(envs) when is_list(envs), do: :prod in envs
  defp available_in_prod?(_env), do: false

  defp fetch_dependency!(app) do
    Enum.find(dependencies(), &(dependency_name(&1) == app)) ||
      flunk("expected dependency #{inspect(app)} to be declared")
  end

  defp dependencies do
    LeanLsp.MixProject.project() |> Keyword.fetch!(:deps)
  end

  defp dependency_name({app, _requirement}), do: app
  defp dependency_name({app, _requirement, _opts}), do: app

  defp dependency_requirement({_app, requirement}) when is_binary(requirement), do: requirement

  defp dependency_requirement({_app, requirement, _opts}) when is_binary(requirement),
    do: requirement

  defp dependency_requirement(_dep), do: nil

  defp dependency_options({_app, opts}) when is_list(opts), do: opts
  defp dependency_options({_app, _requirement}), do: []
  defp dependency_options({_app, _requirement, opts}) when is_list(opts), do: opts

  defp command_present?(steps, fragment) do
    Enum.any?(steps, fn
      step when is_binary(step) -> String.contains?(step, fragment)
      _other -> false
    end)
  end

  defp unsafe_yes_publish_command?(steps) do
    Enum.any?(steps, fn
      step when is_binary(step) ->
        String.contains?(step, "hex.publish") and String.contains?(step, "--yes") and
          not String.contains?(step, "--dry-run")

      _other ->
        false
    end)
  end
end
