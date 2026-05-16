defmodule LeanLsp.Runtime.Docker do
  @moduledoc """
  Docker-backed implementation of `LeanLsp.Runtime`.

  This runtime owns the Docker-specific side effects for the v0.1.0 preview. On
  startup it checks that Docker is available, starts a long-lived container from a
  configurable image, and keeps the container identifier in GenServer state.
  `exec/3` runs commands inside that container with `docker exec`. `stop/1` and
  process termination attempt to stop the backing container.

  The module is intended for runtime-boundary experimentation, not as a complete
  Lean LSP client. It can run Lean-related commands inside Docker, but it does not
  manage JSON-RPC framing, Lean document lifecycle, diagnostics, hover,
  completion, or go-to-definition requests.

  ## External requirements

    * Docker must be installed and reachable by the BEAM process.
    * The current user must have permission to run Docker containers.
    * The selected image must be pullable or already available locally.
    * Host paths used in mounts must be accessible to Docker.

  ## Default image policy

  The default image is `leanprovercommunity/lean4:latest`. The v0.1.0 preview uses
  `latest` as a convenience default so callers can experiment without choosing an
  image first. It is not a reproducibility guarantee. Use a pinned tag or immutable
  digest through `LeanLsp.start_runtime/1`'s `:docker_image` option, or through
  this module's direct `:image` option, when reproducible Lean versions matter.

  ## Runtime options

    * `:image` - Docker image to start. Defaults to
      `LeanLsp.Runtime.Config.default_docker_image/0`.
    * `:workdir`, `:container_workspace_root`, or `:workspace_root` - working
      directory inside the container.
    * `:mounts` - Docker volume mounts as strings, `{host, container}`, or
      `{host, container, mode}` tuples. Bind mounts can expose host files to the
      container; use modes such as `"ro"` for read-only project access.
    * `:env` - environment variables as a map, keyword/list of pairs, or Docker
      `KEY=value` strings.
    * `:container_name` - optional Docker container name.
    * `:docker_run_args` - additional raw arguments passed to `docker run`.
    * `:container_command` - command used to keep the container alive.
    * `:start_timeout` and `:stop_timeout` - Docker command timeouts.

  Execution accepts `:workdir`, `:env`, `:docker_exec_args`, and `:timeout`.

  ## Workspace behaviour

  The default workdir is `/workspace` inside the container. Setting the workdir
  does not automatically mount host files. Host filesystem access is opt-in via
  `:mounts`.

  ## Lifecycle and cleanup

  `start_link/1` creates a long-lived container with `docker run --detach --rm`.
  `stop/1` calls `docker stop`; cleanup is idempotent for an already-stopped
  runtime and treats a missing container as already cleaned up. If startup fails
  after a container is created, the implementation attempts to stop that container
  before returning the startup error.

  ## Docker-related failures

  When Docker is unavailable, startup returns `{:error, reason}`. Common causes
  include a missing Docker executable, Docker not running, insufficient
  permissions, an image that cannot be pulled or started, or invalid runtime
  options. The v0.1.0 public contract is the `{:ok, runtime}` / `{:error, reason}`
  shape; nested Docker error details are implementation-specific preview details.
  """

  @behaviour LeanLsp.Runtime

  use GenServer

  alias LeanLsp.Runtime.ChildSpec
  alias LeanLsp.Runtime.Command
  alias LeanLsp.Runtime.Config, as: RuntimeConfig
  alias LeanLsp.Runtime.Env
  alias LeanLsp.Runtime.Options
  alias LeanLsp.Runtime.SystemCommand

  @default_container_command [
    "sh",
    "-c",
    "trap 'exit 0' TERM INT; while true; do sleep 1; done"
  ]

  @default_start_timeout 30_000
  @default_exec_timeout 30_000
  @default_stop_timeout 15_000
  @default_child_shutdown @default_stop_timeout + 1_000

  defstruct [
    :container_id,
    :container_name,
    :docker,
    :docker_info,
    :image,
    :owner,
    :workdir,
    env: [],
    stopped?: false,
    stop_timeout: @default_stop_timeout
  ]

  @typedoc """
  Runtime process handle for the Docker-backed runtime.

  This is usually the pid or registered name of the GenServer. Treat it as
  opaque and pass it to `exec/3` and `stop/1`.
  """
  @type runtime ::
          pid()
          | atom()
          | {atom(), node()}
          | {:global, term()}
          | {:via, module(), term()}

  @typep docker_command_result :: %{
           required(:stdout) => String.t(),
           required(:stderr) => String.t(),
           required(:exit_status) => non_neg_integer(),
           optional(atom()) => term()
         }

  @doc """
  Returns a child specification suitable for supervisors.

  Runtime options are passed to `start_link/1`. The supervision-specific keys
  `:id`, `:restart`, and `:shutdown` are consumed while building the child spec.

  The default restart mode is `:transient`, so an explicit normal stop does not
  cause the supervisor to restart the runtime. The default shutdown timeout is
  slightly longer than the Docker stop timeout to give container cleanup time to
  finish.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    ChildSpec.build(__MODULE__, opts, @default_child_shutdown)
  end

  @doc """
  Starts a Docker-backed runtime process.

  Startup checks Docker availability, runs `docker run --detach --rm`, and stores
  the resulting container id in the GenServer state. If the GenServer cannot be
  started after the container is created, the implementation attempts to stop the
  container before returning the startup error.

  Important options include `:image`, `:workdir`, `:mounts`, `:env`,
  `:container_name`, `:docker_run_args`, `:container_command`, and
  `:start_timeout`.
  """
  @impl LeanLsp.Runtime
  @spec start_link(LeanLsp.Runtime.options()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {server_opts, runtime_opts} = Keyword.split(opts, Options.gen_server_options())
    runtime_opts = Keyword.put(runtime_opts, :__owner__, self())

    with {:ok, state} <- build_initial_state(runtime_opts) do
      case GenServer.start_link(__MODULE__, state, server_opts) do
        {:ok, _pid} = ok ->
          ok

        {:error, _reason} = error ->
          _ignored = stop_container(state)
          error
      end
    end
  end

  @doc """
  Stops the Docker-backed runtime and cleans up its container.

  This calls `docker stop` for the container owned by the runtime. Cleanup is
  idempotent for an already-stopped runtime and treats a missing container as
  already cleaned up.

  Returns `:ok` when cleanup completes or `{:error, reason}` when Docker cleanup
  fails.
  """
  @impl LeanLsp.Runtime
  @spec stop(LeanLsp.Runtime.t()) :: :ok | {:error, LeanLsp.Runtime.error_reason()}
  def stop(runtime) do
    GenServer.call(runtime, :stop, :infinity)
  end

  @doc """
  Executes a command inside the running Docker container.

  The command must be a non-empty list of strings, for example
  `["lean", "--version"]`. The implementation runs it through `docker exec` and
  captures stdout, stderr, and the exit status.

  Options include `:workdir`, `:env`, `:docker_exec_args`, and `:timeout`.

  Returns `{:ok, result}` for exit status `0`, `{:error, {:command_failed,
  failure}}` for observed non-zero exits, or `{:error, reason}` when the command
  cannot be executed or observed.
  """
  @impl LeanLsp.Runtime
  @spec exec(LeanLsp.Runtime.t(), LeanLsp.Runtime.command(), LeanLsp.Runtime.options()) ::
          {:ok, LeanLsp.Runtime.exec_result()} | {:error, LeanLsp.Runtime.error_reason()}
  def exec(runtime, command, opts) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout, @default_exec_timeout)

    GenServer.call(
      runtime,
      {:exec, command, opts},
      Command.call_timeout(timeout, @default_exec_timeout)
    )
  end

  @impl GenServer
  def init(%__MODULE__{} = state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  defp build_initial_state(opts) do
    with {:ok, config} <- normalize_options(opts),
         {:ok, docker_info} <- DockerAvailability.check(),
         {:ok, container_id} <- start_container(docker_info.executable, config) do
      {:ok,
       %__MODULE__{
         container_id: container_id,
         container_name: config.container_name,
         docker: docker_info.executable,
         docker_info: docker_info,
         env: config.env,
         image: config.image,
         owner: config.owner,
         stop_timeout: config.stop_timeout,
         workdir: config.workdir
       }}
    end
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    case stop_container(state) do
      {:ok, new_state} ->
        {:stop, :normal, :ok, new_state}

      {:error, reason} ->
        {:stop, {:shutdown, reason}, {:error, reason}, mark_stopped(state)}
    end
  end

  def handle_call({:exec, command, opts}, _from, state) do
    {:reply, exec_in_container(state, command, opts), state}
  end

  @impl GenServer
  def handle_info({:EXIT, owner, reason}, %{owner: owner} = state) do
    {:stop, reason, stop_container_for_exit(state)}
  end

  def handle_info({:EXIT, _from, _reason}, state), do: {:noreply, state}
  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    _ignored = stop_container(state)
    :ok
  end

  defp normalize_options(opts) do
    config = %{
      container_command: Keyword.get(opts, :container_command, @default_container_command),
      container_name: Keyword.get(opts, :container_name),
      docker_run_args: Keyword.get(opts, :docker_run_args, []),
      env: Keyword.get(opts, :env, []),
      image: Keyword.get(opts, :image, RuntimeConfig.default_docker_image()),
      mounts: Keyword.get(opts, :mounts, []),
      owner: Keyword.get(opts, :__owner__),
      start_timeout: Keyword.get(opts, :start_timeout, @default_start_timeout),
      stop_timeout: Keyword.get(opts, :stop_timeout, @default_stop_timeout),
      workdir: docker_workdir(opts)
    }

    Options.validate(config,
      image: &Options.non_empty_binary?/1,
      container_command: &Options.string_list?/1,
      docker_run_args: &Options.string_list?/1,
      env: &Env.valid?/1,
      mounts: &valid_mounts?/1,
      container_name: &Options.optional_binary?/1,
      workdir: &Options.optional_binary?/1,
      start_timeout: &Options.valid_timeout?/1,
      stop_timeout: &Options.valid_timeout?/1
    )
  end

  defp docker_workdir(opts) do
    Keyword.get(
      opts,
      :workdir,
      Keyword.get(
        opts,
        :container_workspace_root,
        Keyword.get(opts, :workspace_root, RuntimeConfig.default_container_workspace_root())
      )
    )
  end

  defp start_container(docker, config) do
    args =
      ["run", "--detach", "--rm"] ++
        option_args("--name", config.container_name) ++
        option_args("--workdir", config.workdir) ++
        Env.to_cli_args("--env", config.env) ++
        mount_args(config.mounts) ++
        config.docker_run_args ++
        [config.image] ++
        config.container_command

    case docker_command(docker, args, config.start_timeout) do
      {:ok, %{exit_status: 0, stdout: stdout}} ->
        case String.trim(stdout) do
          "" -> {:error, {:docker_run_failed, :missing_container_id}}
          container_id -> {:ok, container_id}
        end

      {:ok, result} ->
        docker_command_failure(args, result)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stop_container(%__MODULE__{stopped?: true} = state), do: {:ok, state}

  defp stop_container(%__MODULE__{container_id: nil} = state) do
    {:ok, mark_stopped(state)}
  end

  defp stop_container(%__MODULE__{container_id: container_id, docker: docker} = state) do
    args = ["stop", container_id]

    case docker_command(docker, args, state.stop_timeout) do
      {:ok, %{exit_status: 0}} ->
        {:ok, mark_stopped(state)}

      {:ok, result} ->
        if missing_container?(result) do
          {:ok, mark_stopped(state)}
        else
          {:error, {:docker_stop_failed, result.exit_status, Command.output(result)}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stop_container_for_exit(state) do
    case stop_container(state) do
      {:ok, new_state} -> new_state
      {:error, _reason} -> mark_stopped(state)
    end
  end

  defp mark_stopped(state), do: %{state | stopped?: true}

  defp exec_in_container(state, command, opts) do
    with {:ok, command} <- Command.normalize(command),
         {:ok, exec_config} <- normalize_exec_options(state, opts) do
      args =
        ["exec"] ++
          exec_config.docker_exec_args ++
          option_args("--workdir", exec_config.workdir) ++
          Env.to_cli_args("--env", exec_config.env) ++
          [state.container_id] ++
          command

      state.docker
      |> docker_command(args, exec_config.timeout)
      |> Command.normalize_exec_result(command)
    end
  end

  defp normalize_exec_options(state, opts) do
    config = %{
      docker_exec_args: Keyword.get(opts, :docker_exec_args, []),
      env: Keyword.get(opts, :env, []),
      timeout: Keyword.get(opts, :timeout, @default_exec_timeout),
      workdir: Keyword.get(opts, :workdir, state.workdir)
    }

    Options.validate(config,
      docker_exec_args: &Options.string_list?/1,
      env: &Env.valid?/1,
      timeout: &Options.valid_timeout?/1,
      workdir: &Options.optional_binary?/1
    )
  end

  defp docker_command(docker, args, timeout) do
    SystemCommand.run([docker | args],
      timeout: timeout,
      stderr_file_prefix: "lean_lsp_docker_stderr",
      timeout_reason: fn _command, timeout -> {:docker_command_timeout, args, timeout} end,
      crash_reason: fn reason -> {:docker_command_crashed, reason} end,
      launch_reason: fn _command, _executable, exception ->
        {:docker_command_failed, 127, Exception.message(exception)}
      end
    )
  end

  @spec docker_command_failure(LeanLsp.Runtime.command(), docker_command_result()) ::
          {:error,
           {:docker_command_failed, LeanLsp.Runtime.command(), non_neg_integer(), String.t()}}
  defp docker_command_failure(args, result) do
    {:error, {:docker_command_failed, args, result.exit_status, Command.output(result)}}
  end

  @spec missing_container?(docker_command_result()) :: boolean()
  defp missing_container?(result) do
    result
    |> Command.output()
    |> String.downcase()
    |> String.contains?("no such container")
  end

  defp option_args(_option, nil), do: []
  defp option_args(_option, ""), do: []
  defp option_args(option, value), do: [option, value]

  defp mount_args(mounts) when is_list(mounts) do
    Enum.flat_map(mounts, fn
      mount when is_binary(mount) ->
        ["--volume", mount]

      {host_path, container_path} ->
        ["--volume", "#{host_path}:#{container_path}"]

      {host_path, container_path, mode} ->
        ["--volume", "#{host_path}:#{container_path}:#{mode}"]
    end)
  end

  defp valid_mounts?(mounts) when is_list(mounts) do
    Enum.all?(mounts, fn
      mount when is_binary(mount) ->
        mount != ""

      {host_path, container_path} ->
        Options.non_empty_binary?(host_path) and Options.non_empty_binary?(container_path)

      {host_path, container_path, mode} ->
        Options.non_empty_binary?(host_path) and Options.non_empty_binary?(container_path) and
          Options.non_empty_binary?(mode)

      _other ->
        false
    end)
  end

  defp valid_mounts?(_mounts), do: false
end
