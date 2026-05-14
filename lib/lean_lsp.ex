defmodule LeanLsp do
  @moduledoc """
  Public API for `LeanLsp`.
  """

  alias LeanLsp.Runtime.Config

  @doc """
  Normalizes runtime configuration without starting a runtime.
  """
  @spec runtime_config(keyword()) :: {:ok, Config.t()} | {:error, term()}
  def runtime_config(opts \\ []) do
    Config.normalize(opts)
  end

  @doc """
  Starts the configured runtime.

  By default this starts `LeanLsp.Runtime.Docker`. Tests and callers can pass
  `:runtime` to use another implementation of `LeanLsp.Runtime`.

  ## Examples

      LeanLsp.start_runtime(
        docker_image: "leanprovercommunity/lean4:latest",
        container_workspace_root: "/workspace"
      )

      LeanLsp.start_runtime(
        runtime: MyApp.FakeRuntime,
        runtime_options: [workdir: "/test-workspace"]
      )
  """
  @spec start_runtime(keyword()) ::
          {:ok, LeanLsp.Runtime.t()} | {:error, LeanLsp.Runtime.error_reason()}
  def start_runtime(opts \\ []) do
    with {:ok, config} <- Config.normalize(opts) do
      config.runtime.start_link(Config.to_runtime_options(config))
    end
  end
end
