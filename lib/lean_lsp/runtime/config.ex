defmodule LeanLsp.Runtime.Config do
  @moduledoc """
  Normalized runtime configuration for LeanLsp.

  This module keeps runtime selection and runtime defaults explicit. It does not
  start Docker, create containers, or allocate external resources; it only
  validates options and converts them into the option shape expected by the
  selected runtime implementation.

  The default runtime is `LeanLsp.Runtime.Docker`, but callers can pass
  `:runtime` to use a test runtime or another module that implements
  `LeanLsp.Runtime`.

  ## Supported options

    * `:runtime` - runtime implementation module.
    * `:docker_image` - Docker image used by the default Docker runtime.
    * `:container_workspace_root` - working directory inside the container.
    * `:workspace_root` - alias for `:container_workspace_root`.
    * `:runtime_options` - keyword options passed directly to the selected
      runtime.

  Additional keyword options are merged into `:runtime_options`. This lets
  callers pass runtime-specific options such as `:mounts`, `:env`, or timeouts
  without changing the top-level `LeanLsp` API.

  ## Defaults

    * `:runtime` - `LeanLsp.Runtime.Docker`
    * `:docker_image` - `"leanprovercommunity/lean4:latest"`
    * `:container_workspace_root` - `"/workspace"`

  `:container_workspace_root` is the path inside the container. Host workspace
  mounting remains a runtime concern and should be handled with runtime-specific
  mount options.
  """

  @default_runtime LeanLsp.Runtime.Docker
  @default_docker_image "leanprovercommunity/lean4:latest"
  @default_container_workspace_root "/workspace"

  @known_options [
    :runtime,
    :runtime_options,
    :docker_image,
    :container_workspace_root,
    :workspace_root
  ]

  defstruct runtime: @default_runtime,
            docker_image: @default_docker_image,
            container_workspace_root: @default_container_workspace_root,
            runtime_options: []

  @type t :: %__MODULE__{
          runtime: module(),
          docker_image: String.t(),
          container_workspace_root: String.t(),
          runtime_options: keyword()
        }

  @doc group: "Defaults"
  @doc """
  Returns the runtime module used by default.

  In v0.1.0 this is `LeanLsp.Runtime.Docker`.
  """
  @spec default_runtime() :: module()
  def default_runtime(), do: @default_runtime

  @doc group: "Defaults"
  @doc """
  Returns the Docker image used by the default Docker runtime.
  """
  @spec default_docker_image() :: String.t()
  def default_docker_image(), do: @default_docker_image

  @doc group: "Defaults"
  @doc """
  Returns the default working directory inside the Docker container.
  """
  @spec default_container_workspace_root() :: String.t()
  def default_container_workspace_root(), do: @default_container_workspace_root

  @doc group: "Normalization"
  @doc """
  Validates and normalizes user-provided runtime options.

  Returns `{:ok, config}` when the options are a keyword list, the runtime module
  implements `LeanLsp.Runtime`, Docker-specific defaults are valid, and
  `:runtime_options` is a keyword list.

  Returns `{:error, {:invalid_options, value}}` when the input is not a keyword
  list, or `{:error, {:invalid_option, key}}` when a specific option is invalid.
  This function does not start Docker or create a runtime.
  """
  @spec normalize(keyword()) :: {:ok, t()} | {:error, term()}
  def normalize(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> build_config()
      |> validate_config()
    else
      {:error, {:invalid_options, opts}}
    end
  end

  def normalize(opts), do: {:error, {:invalid_options, opts}}

  @doc group: "Normalization"
  @doc """
  Converts a normalized config into options for the selected runtime.

  For `LeanLsp.Runtime.Docker`, this maps the public configuration fields to the
  Docker runtime option names by setting `:image` and `:workdir`, then merges any
  runtime-specific options.

  For non-Docker runtimes, this returns `config.runtime_options` unchanged.
  """
  @spec to_runtime_options(t()) :: keyword()
  def to_runtime_options(%__MODULE__{runtime: LeanLsp.Runtime.Docker} = config) do
    config.runtime_options
    |> Keyword.put(:image, config.docker_image)
    |> Keyword.put(:workdir, config.container_workspace_root)
  end

  def to_runtime_options(%__MODULE__{} = config), do: config.runtime_options

  defp build_config(opts) do
    %__MODULE__{
      runtime: Keyword.get(opts, :runtime, @default_runtime),
      docker_image: Keyword.get(opts, :docker_image, @default_docker_image),
      container_workspace_root: container_workspace_root(opts),
      runtime_options: runtime_options(opts)
    }
  end

  defp container_workspace_root(opts) do
    Keyword.get(
      opts,
      :container_workspace_root,
      Keyword.get(opts, :workspace_root, @default_container_workspace_root)
    )
  end

  defp runtime_options(opts) do
    explicit_runtime_options = Keyword.get(opts, :runtime_options, [])

    if keyword?(explicit_runtime_options) do
      opts
      |> Keyword.drop(@known_options)
      |> Keyword.merge(explicit_runtime_options)
    else
      explicit_runtime_options
    end
  end

  defp validate_config(%__MODULE__{} = config) do
    cond do
      not runtime_module?(config.runtime) ->
        {:error, {:invalid_option, :runtime}}

      not non_empty_binary?(config.docker_image) ->
        {:error, {:invalid_option, :docker_image}}

      not absolute_container_path?(config.container_workspace_root) ->
        {:error, {:invalid_option, :container_workspace_root}}

      not keyword?(config.runtime_options) ->
        {:error, {:invalid_option, :runtime_options}}

      true ->
        {:ok, config}
    end
  end

  defp runtime_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      Enum.all?(LeanLsp.Runtime.behaviour_info(:callbacks), fn {name, arity} ->
        function_exported?(module, name, arity)
      end)
  end

  defp runtime_module?(_module), do: false

  defp keyword?(value), do: is_list(value) and Keyword.keyword?(value)

  defp absolute_container_path?(value) do
    non_empty_binary?(value) and String.starts_with?(value, "/")
  end

  defp non_empty_binary?(value), do: is_binary(value) and value != ""
end
