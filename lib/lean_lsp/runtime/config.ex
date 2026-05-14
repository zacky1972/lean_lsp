defmodule LeanLsp.Runtime.Config do
  @moduledoc """
  Runtime configuration for LeanLsp.

  This module keeps runtime selection and runtime defaults explicit. The default
  runtime is `LeanLsp.Runtime.Docker`, but callers can pass `:runtime` to use a
  test runtime or another implementation of `LeanLsp.Runtime`.

  ## Defaults

    * `:runtime` - `LeanLsp.Runtime.Docker`
    * `:docker_image` - `"leanprovercommunity/lean4:latest"`
    * `:container_workspace_root` - `"/workspace"`

  `:container_workspace_root` is the path inside the container. Host workspace
  mounting remains a runtime concern and should be handled by workspace/mount
  options.
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

  @spec default_runtime() :: module()
  def default_runtime(), do: @default_runtime

  @spec default_docker_image() :: String.t()
  def default_docker_image(), do: @default_docker_image

  @spec default_container_workspace_root() :: String.t()
  def default_container_workspace_root(), do: @default_container_workspace_root

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
