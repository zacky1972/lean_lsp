defmodule LeanLsp do
  @moduledoc """
  Public entry point for the LeanLsp v0.1.0 runtime preview.

  This module exposes the narrow public API that is available in the initial
  Hex release: runtime configuration and runtime startup. Higher-level Lean LSP
  sessions, document lifecycle helpers, diagnostics, hover, completion, and
  go-to-definition APIs are roadmap work and are intentionally not exposed as a
  stable v0.1.0 surface.

  The default runtime is `LeanLsp.Runtime.Docker`. Starting it has Docker side
  effects: a container is created, commands can be executed inside it, and the
  caller is responsible for stopping the runtime when it is no longer needed.
  """

  alias LeanLsp.Runtime.Config

  @doc group: "Runtime configuration"
  @doc """
  Normalizes runtime configuration without starting a runtime.

  Use this function when you want to validate user options or inspect the
  runtime implementation and defaults before starting any external resources.
  It has no Docker side effects.

  Accepted options include:

    * `:runtime` - runtime implementation module. Defaults to
      `LeanLsp.Runtime.Docker`.
    * `:docker_image` - Docker image used by the default Docker runtime.
    * `:container_workspace_root` - working directory inside the container.
    * `:workspace_root` - backwards-compatible alias for
      `:container_workspace_root`.
    * `:runtime_options` - keyword options passed to the selected runtime.

  Additional keyword options are merged into `:runtime_options`, allowing callers
  to pass runtime-specific options such as Docker mounts or timeouts.

  Returns `{:ok, %LeanLsp.Runtime.Config{}}` on success or `{:error, reason}`
  when the option list is invalid.
  """
  @spec runtime_config(keyword()) :: {:ok, Config.t()} | {:error, term()}
  def runtime_config(opts \\ []) do
    Config.normalize(opts)
  end

  @doc group: "Runtime lifecycle"
  @doc """
  Starts the configured runtime.

  By default this starts `LeanLsp.Runtime.Docker`, which checks for a reachable
  Docker executable and creates a long-lived Docker container. The returned
  runtime handle should be passed to the runtime implementation for command
  execution and cleanup.

  Callers that start the Docker runtime directly are responsible for stopping it
  with `LeanLsp.Runtime.Docker.stop/1` when finished. Supervised callers can use
  `LeanLsp.Runtime.Docker.child_spec/1` instead.

  ## Examples

      {:ok, runtime} =
        LeanLsp.start_runtime(
          docker_image: "leanprovercommunity/lean4:latest",
          container_workspace_root: "/workspace"
        )

      {:ok, %{stdout: stdout, exit_status: 0}} =
        LeanLsp.Runtime.Docker.exec(runtime, ["lean", "--version"], [])

      :ok = LeanLsp.Runtime.Docker.stop(runtime)

  Tests and callers can pass `:runtime` to use another implementation of
  `LeanLsp.Runtime`.

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
