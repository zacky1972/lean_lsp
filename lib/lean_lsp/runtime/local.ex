defmodule LeanLsp.Runtime.Local do
  @moduledoc """
  Host-backed implementation of `LeanLsp.Runtime`.

  This runtime executes Lean-related commands directly on the host machine. It is
  useful for local development environments where Lean, Lake, and Elan are
  already installed and Docker isolation is not required.

  Docker remains the default runtime selected by `LeanLsp.Runtime.Config`; select
  this runtime explicitly when host execution is desired.

  ## Runtime options

    * `:workdir`, `:workspace_root`, or `:container_workspace_root` - host
      directory where commands are executed. Defaults to `File.cwd!/0`.
    * `:env` - environment variables as a map, keyword/list of pairs, or
      `"KEY=value"` strings.
    * `:timeout` or `:exec_timeout` - default command timeout in milliseconds.

  ## Examples

      {:ok, runtime} =
        LeanLsp.start_runtime(
          runtime: LeanLsp.Runtime.Local,
          workdir: File.cwd!()
        )

      {:ok, result} =
        LeanLsp.Runtime.Local.exec(runtime, ["lake", "--version"], timeout: 120_000)

      :ok = LeanLsp.Runtime.Local.stop(runtime)

  Lake builds can be executed through the same runtime contract:

      {:ok, result} =
        LeanLsp.Runtime.Local.exec(runtime, ["lake", "build"], timeout: 120_000)

  The runtime captures `stdout`, `stderr`, and `exit_status`. Observed non-zero
  exits return `{:error, {:command_failed, failure}}`; launch failures and
  timeouts return structured errors without requiring callers to parse text.
  """

  @behaviour LeanLsp.Runtime

  use GenServer

  @default_exec_timeout 30_000
  @default_child_shutdown @default_exec_timeout + 1_000
  @gen_server_options [:debug, :hibernate_after, :name, :spawn_opt]

  defstruct [
    :owner,
    :workdir,
    env: [],
    stopped?: false,
    timeout: @default_exec_timeout
  ]

  @typedoc """
  Runtime process handle for the host-backed runtime.
  """
  @type runtime ::
          pid()
          | atom()
          | {atom(), node()}
          | {:global, term()}
          | {:via, module(), term()}

  @doc """
  Returns a child specification suitable for supervisors.
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

  @doc """
  Starts a host-backed runtime process.
  """
  @impl LeanLsp.Runtime
  @spec start_link(LeanLsp.Runtime.options()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    if keyword?(opts) do
      {server_opts, runtime_opts} = Keyword.split(opts, @gen_server_options)
      runtime_opts = Keyword.put(runtime_opts, :__owner__, self())

      with {:ok, state} <- build_initial_state(runtime_opts) do
        GenServer.start_link(__MODULE__, state, server_opts)
      end
    else
      {:error, {:invalid_options, opts}}
    end
  end

  def start_link(opts), do: {:error, {:invalid_options, opts}}

  @doc """
  Stops the host-backed runtime.

  Cleanup is idempotent for a runtime process that has already stopped.
  """
  @impl LeanLsp.Runtime
  @spec stop(LeanLsp.Runtime.t()) :: :ok | {:error, LeanLsp.Runtime.error_reason()}
  def stop(runtime) do
    GenServer.call(runtime, :stop, :infinity)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, {:normal, _call} -> :ok
    :exit, reason -> {:error, {:runtime_stop_failed, runtime, reason}}
  end

  @doc """
  Executes a command on the host.

  The command must be a non-empty list of strings, for example
  `["lake", "--version"]`. Options include `:workdir`, `:env`, and `:timeout`.
  """
  @impl LeanLsp.Runtime
  @spec exec(LeanLsp.Runtime.t(), LeanLsp.Runtime.command(), LeanLsp.Runtime.options()) ::
          {:ok, LeanLsp.Runtime.exec_result()} | {:error, LeanLsp.Runtime.error_reason()}
  def exec(runtime, command, opts) when is_list(opts) do
    if keyword?(opts) do
      GenServer.call(runtime, {:exec, command, opts}, exec_call_timeout(opts))
    else
      {:error, {:invalid_options, opts}}
    end
  catch
    :exit, {:noproc, _call} -> {:error, {:runtime_not_running, runtime}}
    :exit, reason -> {:error, {:runtime_call_failed, runtime, reason}}
  end

  def exec(_runtime, _command, opts), do: {:error, {:invalid_options, opts}}

  @impl GenServer
  def init(%__MODULE__{} = state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, mark_stopped(state)}
  end

  def handle_call({:exec, command, opts}, _from, state) do
    {:reply, exec_on_host(state, command, opts), state}
  end

  @impl GenServer
  def handle_info({:EXIT, owner, reason}, %{owner: owner} = state) do
    {:stop, reason, mark_stopped(state)}
  end

  def handle_info({:EXIT, _from, _reason}, state), do: {:noreply, state}
  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, _state), do: :ok

  defp build_initial_state(opts) do
    with {:ok, config} <- normalize_options(opts) do
      {:ok,
       %__MODULE__{
         env: config.env,
         owner: config.owner,
         timeout: config.timeout,
         workdir: config.workdir
       }}
    end
  end

  defp normalize_options(opts) do
    config = %{
      env: Keyword.get(opts, :env, []),
      owner: Keyword.get(opts, :__owner__),
      timeout: Keyword.get(opts, :timeout, Keyword.get(opts, :exec_timeout, @default_exec_timeout)),
      workdir: host_workdir(opts)
    }

    with {:ok, env} <- normalize_env(config.env),
         {:ok, workdir} <- normalize_workdir(config.workdir),
         {:ok, timeout} <- normalize_timeout(config.timeout) do
      {:ok, %{config | env: env, timeout: timeout, workdir: workdir}}
    end
  end

  defp host_workdir(opts) do
    Keyword.get(
      opts,
      :workdir,
      Keyword.get(
        opts,
        :workspace_root,
        Keyword.get(opts, :container_workspace_root, File.cwd!())
      )
    )
  end

  defp exec_on_host(state, command, opts) do
    with {:ok, command} <- normalize_command(command),
         {:ok, exec_config} <- normalize_exec_options(state, opts),
         {:ok, command} <- ensure_command_launchable(command, exec_config) do
      command
      |> host_command(exec_config)
      |> normalize_exec_result(command)
    end
  end

  defp normalize_exec_options(state, opts) do
    config = %{
      env: Keyword.get(opts, :env, []),
      timeout: Keyword.get(opts, :timeout, state.timeout),
      workdir: Keyword.get(opts, :workdir, state.workdir)
    }

    with {:ok, exec_env} <- normalize_env(config.env),
         {:ok, workdir} <- normalize_workdir(config.workdir),
         {:ok, timeout} <- normalize_timeout(config.timeout) do
      {:ok, %{config | env: merge_env(state.env, exec_env), timeout: timeout, workdir: workdir}}
    end
  end

  defp normalize_command([executable | _args] = command) when is_binary(executable) do
    cond do
      executable == "" ->
        {:error, {:invalid_command, command}}

      Enum.all?(command, &is_binary/1) ->
        {:ok, command}

      true ->
        {:error, {:invalid_command, command}}
    end
  end

  defp normalize_command(command), do: {:error, {:invalid_command, command}}

  defp ensure_command_launchable([executable | _args] = command, config) do
    if executable_available?(executable, config.workdir, config.env) do
      {:ok, command}
    else
      {:error,
       {:command_launch_failed,
        %{
          command: command,
          executable: executable,
          reason: :enoent
        }}}
    end
  end

  defp host_command(command, config) do
    parent = self()
    command_ref = make_ref()
    stderr_path = stderr_path()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        send(parent, {command_ref, capture_command(command, config, stderr_path)})
      end)

    receive_command_result(pid, monitor_ref, command_ref, command, stderr_path, config.timeout)
  end

  defp receive_command_result(pid, monitor_ref, command_ref, _command, _stderr_path, :infinity) do
    receive do
      {^command_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        receive_result_after_down(command_ref, reason)
    end
  end

  defp receive_command_result(pid, monitor_ref, command_ref, command, stderr_path, timeout) do
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
        File.rm(stderr_path)
        {:error, {:command_timeout, command, timeout}}
    end
  end

  defp receive_result_after_down(command_ref, reason) do
    receive do
      {^command_ref, result} -> result
    after
      0 -> {:error, {:command_crashed, reason}}
    end
  end

  defp capture_command([executable | args] = command, config, stderr_path) do
    try do
      {stdout, exit_status} =
        System.cmd(
          "/bin/sh",
          [
            "-c",
            "err=$1; shift; exec \"$@\" 2>\"$err\"",
            "lean_lsp_local",
            stderr_path,
            executable | args
          ],
          cd: config.workdir,
          env: config.env
        )

      {:ok,
       %{
         exit_status: exit_status,
         stderr: read_file(stderr_path),
         stdout: stdout
       }}
    rescue
      exception in [ArgumentError, ErlangError] ->
        {:error,
         {:command_launch_failed,
          %{
            command: command,
            executable: executable,
            reason: Exception.message(exception)
          }}}
    after
      File.rm(stderr_path)
    end
  end

  defp normalize_exec_result({:ok, %{exit_status: 0} = result}, _command) do
    {:ok, result}
  end

  defp normalize_exec_result(
         {:ok, %{exit_status: exit_status, stdout: stdout, stderr: stderr}},
         command
       ) do
    {:error,
     {:command_failed,
      %{
        command: command,
        stdout: stdout,
        stderr: stderr,
        exit_status: exit_status
      }}}
  end

  defp normalize_exec_result({:error, _reason} = error, _command), do: error

  defp normalize_workdir(value) when is_binary(value) and value != "" do
    workdir = Path.expand(value)

    if File.dir?(workdir) do
      {:ok, workdir}
    else
      {:error, {:invalid_option, :workdir}}
    end
  end

  defp normalize_workdir(_value), do: {:error, {:invalid_option, :workdir}}

  defp normalize_timeout(:infinity), do: {:ok, :infinity}

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout >= 0 do
    {:ok, timeout}
  end

  defp normalize_timeout(_timeout), do: {:error, {:invalid_option, :timeout}}

  defp normalize_env(nil), do: {:ok, []}

  defp normalize_env(env) when is_map(env) do
    env
    |> Map.to_list()
    |> normalize_env()
  end

  defp normalize_env(env) when is_list(env) do
    case Enum.reduce_while(env, {:ok, []}, fn entry, {:ok, entries} ->
           case normalize_env_entry(entry) do
             {:ok, pair} -> {:cont, {:ok, [pair | entries]}}
             {:error, reason} -> {:halt, {:error, reason}}
           end
         end) do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_env(_env), do: {:error, {:invalid_option, :env}}

  defp normalize_env_entry(value) when is_binary(value) do
    case String.split(value, "=", parts: 2) do
      [key, env_value] when key != "" -> {:ok, {key, env_value}}
      _other -> {:error, {:invalid_option, :env}}
    end
  end

  defp normalize_env_entry({key, value}) do
    with {:ok, key} <- normalize_env_key(key),
         {:ok, value} <- normalize_env_value(value) do
      {:ok, {key, value}}
    else
      {:error, _reason} -> {:error, {:invalid_option, :env}}
    end
  end

  defp normalize_env_entry(_value), do: {:error, {:invalid_option, :env}}

  defp normalize_env_key(key) when is_atom(key), do: normalize_env_key(Atom.to_string(key))

  defp normalize_env_key(key) when is_binary(key) do
    if key != "" and not String.contains?(key, "=") do
      {:ok, key}
    else
      {:error, :invalid_env_key}
    end
  end

  defp normalize_env_key(_key), do: {:error, :invalid_env_key}

  defp normalize_env_value(value) when is_binary(value), do: {:ok, value}

  defp normalize_env_value(value)
       when is_atom(value) or is_integer(value) or is_float(value) or is_boolean(value) do
    {:ok, to_string(value)}
  end

  defp normalize_env_value(_value), do: {:error, :invalid_env_value}

  defp merge_env(runtime_env, exec_env) do
    runtime_env
    |> Map.new()
    |> Map.merge(Map.new(exec_env))
    |> Map.to_list()
  end

  defp executable_available?(executable, workdir, env) do
    if path_command?(executable) do
      executable
      |> executable_path(workdir)
      |> executable_file?()
    else
      executable
      |> find_on_path(workdir, env)
      |> is_binary()
    end
  end

  defp path_command?(executable), do: String.contains?(executable, "/")

  defp executable_path(executable, workdir) do
    case Path.type(executable) do
      :absolute -> executable
      _relative_or_volume_relative -> Path.expand(executable, workdir)
    end
  end

  defp find_on_path(executable, workdir, env) do
    env
    |> path_env()
    |> String.split(path_separator(), trim: false)
    |> Enum.map(&path_entry_to_dir(&1, workdir))
    |> Enum.map(&Path.join(&1, executable))
    |> Enum.find(&executable_file?/1)
  end

  defp path_env(env) do
    case Enum.find(env, fn {key, _value} -> key == "PATH" end) do
      {"PATH", value} -> value
      nil -> System.get_env("PATH", "")
    end
  end

  defp path_entry_to_dir("", workdir), do: workdir
  defp path_entry_to_dir(path, _workdir), do: path

  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _other -> false
    end
  end

  defp path_separator do
    case :os.type() do
      {:win32, _name} -> ";"
      _other -> ":"
    end
  end

  defp stderr_path do
    Path.join(
      System.tmp_dir!(),
      "lean_lsp_local_stderr_#{System.unique_integer([:positive])}.log"
    )
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, _reason} -> ""
    end
  end

  defp exec_call_timeout(opts) do
    case Keyword.fetch(opts, :timeout) do
      {:ok, timeout} -> call_timeout(timeout)
      :error -> :infinity
    end
  end

  defp call_timeout(:infinity), do: :infinity

  defp call_timeout(timeout) when is_integer(timeout) and timeout >= 0 do
    timeout + 1_000
  end

  defp call_timeout(_timeout), do: @default_exec_timeout + 1_000

  defp mark_stopped(state), do: %{state | stopped?: true}

  defp keyword?(value), do: is_list(value) and Keyword.keyword?(value)
end
