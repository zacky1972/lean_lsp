defmodule LeanLsp.Runtime.Docker do
  @moduledoc """
  Docker-backed runtime implementation for `LeanLsp.Runtime`.

  This module owns Docker-specific runtime concerns. It starts a long-lived
  container from a configurable image, tracks the container identity in process
  state, executes commands inside the container, and stops the backing container
  when the runtime stops.
  """

  @behaviour LeanLsp.Runtime

  use GenServer

  @default_image "leanprovercommunity/lean4:latest"

  @default_container_command [
    "sh",
    "-c",
    "trap 'exit 0' TERM INT; while true; do sleep 1; done"
  ]

  @default_start_timeout 30_000
  @default_exec_timeout 30_000
  @default_stop_timeout 15_000
  @default_child_shutdown @default_stop_timeout + 1_000

  @gen_server_options [:debug, :hibernate_after, :name, :spawn_opt]

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
  Runtime process handle.
  """
  @type runtime ::
          pid()
          | atom()
          | {atom(), node()}
          | {:global, term()}
          | {:via, module(), term()}

  @doc """
  Returns a child specification suitable for supervisors.

  The default restart mode is `:transient`, so an explicit normal stop does not
  cause the supervisor to restart the runtime.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    runtime_opts = Keyword.drop(opts, [:id, :restart, :shutdown])

    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [runtime_opts]},
      restart: Keyword.get(opts, :restart, :transient),
      shutdown: Keyword.get(opts, :shutdown, @default_child_shutdown),
      type: :worker
    }
  end

  @impl LeanLsp.Runtime
  @spec start_link(LeanLsp.Runtime.options()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {server_opts, runtime_opts} = Keyword.split(opts, @gen_server_options)
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

  @impl LeanLsp.Runtime
  @spec stop(LeanLsp.Runtime.t()) :: :ok | {:error, LeanLsp.Runtime.error_reason()}
  def stop(runtime) do
    GenServer.call(runtime, :stop, :infinity)
  end

  @impl LeanLsp.Runtime
  @spec exec(LeanLsp.Runtime.t(), LeanLsp.Runtime.command(), LeanLsp.Runtime.options()) ::
          {:ok, LeanLsp.Runtime.exec_result()} | {:error, LeanLsp.Runtime.error_reason()}
  def exec(runtime, command, opts) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout, @default_exec_timeout)

    GenServer.call(runtime, {:exec, command, opts}, call_timeout(timeout))
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

  def handle_info({:EXIT, _from, _reason}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

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
      image:
        Keyword.get(opts, :image, Application.get_env(:lean_lsp, :docker_image, @default_image)),
      mounts: Keyword.get(opts, :mounts, []),
      owner: Keyword.get(opts, :__owner__),
      start_timeout: Keyword.get(opts, :start_timeout, @default_start_timeout),
      stop_timeout: Keyword.get(opts, :stop_timeout, @default_stop_timeout),
      workdir: Keyword.get(opts, :workdir)
    }

    validate_options(config,
      image: &non_empty_binary?/1,
      container_command: &string_list?/1,
      docker_run_args: &string_list?/1,
      env: &valid_env?/1,
      mounts: &valid_mounts?/1,
      container_name: &optional_binary?/1,
      workdir: &optional_binary?/1,
      start_timeout: &valid_timeout?/1,
      stop_timeout: &valid_timeout?/1
    )
  end

  defp validate_options(config, validators) do
    case Enum.find(validators, fn {key, validator} -> not validator.(Map.fetch!(config, key)) end) do
      nil -> {:ok, config}
      {key, _validator} -> {:error, {:invalid_option, key}}
    end
  end

  defp start_container(docker, config) do
    args =
      ["run", "--detach", "--rm"] ++
        option_args("--name", config.container_name) ++
        option_args("--workdir", config.workdir) ++
        env_args(config.env) ++
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
          {:error, {:docker_stop_failed, result.exit_status, command_output(result)}}
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

  defp mark_stopped(state) do
    %{state | stopped?: true}
  end

  defp exec_in_container(state, command, opts) do
    with {:ok, command} <- normalize_command(command),
         {:ok, exec_config} <- normalize_exec_options(state, opts) do
      args =
        ["exec"] ++
          exec_config.docker_exec_args ++
          option_args("--workdir", exec_config.workdir) ++
          env_args(exec_config.env) ++
          [state.container_id] ++
          command

      docker_command(state.docker, args, exec_config.timeout)
    end
  end

  defp normalize_exec_options(state, opts) do
    config = %{
      docker_exec_args: Keyword.get(opts, :docker_exec_args, []),
      env: Keyword.get(opts, :env, []),
      timeout: Keyword.get(opts, :timeout, @default_exec_timeout),
      workdir: Keyword.get(opts, :workdir, state.workdir)
    }

    validate_options(config,
      docker_exec_args: &string_list?/1,
      env: &valid_env?/1,
      timeout: &valid_timeout?/1,
      workdir: &optional_binary?/1
    )
  end

  defp normalize_command(command) when is_list(command) do
    if command != [] and Enum.all?(command, &is_binary/1) do
      {:ok, command}
    else
      {:error, {:invalid_command, command}}
    end
  end

  defp normalize_command(command), do: {:error, {:invalid_command, command}}

  defp docker_command(docker, args, timeout) do
    parent = self()
    command_ref = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        send(parent, {command_ref, capture_command(docker, args)})
      end)

    receive_command_result(pid, monitor_ref, command_ref, args, timeout)
  end

  defp receive_command_result(pid, monitor_ref, command_ref, _args, :infinity) do
    receive do
      {^command_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        receive_result_after_down(command_ref, reason)
    end
  end

  defp receive_command_result(pid, monitor_ref, command_ref, args, timeout) do
    receive do
      {^command_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        receive_result_after_down(command_ref, reason)
    after
      timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor_ref, [:flush])
        {:error, {:docker_command_timeout, args, timeout}}
    end
  end

  defp receive_result_after_down(command_ref, reason) do
    receive do
      {^command_ref, result} -> result
    after
      0 -> {:error, {:docker_command_crashed, reason}}
    end
  end

  defp capture_command(docker, args) do
    stderr_path = stderr_path()

    try do
      {stdout, exit_status} =
        System.cmd("/bin/sh", [
          "-c",
          "err=$1; shift; exec \"$@\" 2>\"$err\"",
          "lean_lsp_docker",
          stderr_path,
          docker | args
        ])

      {:ok,
       %{
         exit_status: exit_status,
         stderr: read_file(stderr_path),
         stdout: stdout
       }}
    rescue
      exception in [ArgumentError, ErlangError] ->
        {:error, {:docker_command_failed, 127, Exception.message(exception)}}
    after
      File.rm(stderr_path)
    end
  end

  defp stderr_path() do
    Path.join(
      System.tmp_dir!(),
      "lean_lsp_docker_stderr_#{System.unique_integer([:positive])}.log"
    )
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, _reason} -> ""
    end
  end

  defp docker_command_failure(args, result) do
    {:error, {:docker_command_failed, args, result.exit_status, command_output(result)}}
  end

  defp command_output(result) do
    [result.stdout, result.stderr]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> String.trim()
  end

  defp missing_container?(result) do
    result
    |> command_output()
    |> String.downcase()
    |> String.contains?("no such container")
  end

  defp call_timeout(:infinity), do: :infinity

  defp call_timeout(timeout) when is_integer(timeout) and timeout >= 0 do
    timeout + 1_000
  end

  defp call_timeout(_timeout), do: @default_exec_timeout + 1_000

  defp option_args(_option, nil), do: []
  defp option_args(_option, ""), do: []
  defp option_args(option, value), do: [option, value]

  defp env_args(nil), do: []

  defp env_args(env) when is_map(env) do
    env
    |> Map.to_list()
    |> env_args()
  end

  defp env_args(env) when is_list(env) do
    Enum.flat_map(env, fn
      value when is_binary(value) ->
        ["--env", value]

      {key, value} ->
        ["--env", "#{env_part_to_string(key)}=#{env_part_to_string(value)}"]
    end)
  end

  defp env_part_to_string(value) when is_binary(value), do: value
  defp env_part_to_string(value), do: to_string(value)

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

  defp string_list?(value) when is_list(value), do: Enum.all?(value, &is_binary/1)
  defp string_list?(_value), do: false

  defp valid_env?(nil), do: true

  defp valid_env?(env) when is_map(env) do
    Enum.all?(env, fn {key, value} -> valid_env_entry?({key, value}) end)
  end

  defp valid_env?(env) when is_list(env) do
    Enum.all?(env, &valid_env_entry?/1)
  end

  defp valid_env?(_env), do: false

  defp valid_env_entry?(value) when is_binary(value), do: value != ""

  defp valid_env_entry?({key, value}) do
    valid_env_key?(key) and valid_env_value?(value)
  end

  defp valid_env_entry?(_value), do: false

  defp valid_env_key?(key), do: is_atom(key) or is_binary(key)

  defp valid_env_value?(value)
       when is_binary(value)
       when is_atom(value)
       when is_integer(value)
       when is_float(value)
       when is_boolean(value) do
    true
  end

  defp valid_env_value?(_value), do: false

  defp valid_mounts?(mounts) when is_list(mounts) do
    Enum.all?(mounts, fn
      mount when is_binary(mount) ->
        mount != ""

      {host_path, container_path} ->
        non_empty_binary?(host_path) and non_empty_binary?(container_path)

      {host_path, container_path, mode} ->
        non_empty_binary?(host_path) and non_empty_binary?(container_path) and
          non_empty_binary?(mode)

      _other ->
        false
    end)
  end

  defp valid_mounts?(_mounts), do: false

  defp optional_binary?(nil), do: true
  defp optional_binary?(value), do: non_empty_binary?(value)

  defp non_empty_binary?(value), do: is_binary(value) and value != ""

  defp valid_timeout?(:infinity), do: true
  defp valid_timeout?(timeout), do: is_integer(timeout) and timeout >= 0
end
