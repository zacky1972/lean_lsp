defmodule LeanLsp.Runtime.SystemCommand do
  @moduledoc false

  @default_stderr_file_prefix "lean_lsp_runtime_stderr"

  @spec run(LeanLsp.Runtime.command(), keyword()) ::
          {:ok, LeanLsp.Runtime.exec_result()} | {:error, LeanLsp.Runtime.error_reason()}
  def run([executable | args] = command, opts) when is_binary(executable) and is_list(args) do
    timeout = Keyword.fetch!(opts, :timeout)
    system_opts = Keyword.get(opts, :system_opts, [])
    stderr_path = stderr_path(Keyword.get(opts, :stderr_file_prefix, @default_stderr_file_prefix))
    parent = self()
    command_ref = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        send(parent, {command_ref, capture(command, system_opts, stderr_path, opts)})
      end)

    receive_command_result(pid, monitor_ref, command_ref, command, stderr_path, timeout, opts)
  end

  defp receive_command_result(
         pid,
         monitor_ref,
         command_ref,
         _command,
         _stderr_path,
         :infinity,
         opts
       ) do
    receive do
      {^command_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        receive_result_after_down(command_ref, reason, opts)
    end
  end

  defp receive_command_result(pid, monitor_ref, command_ref, command, stderr_path, timeout, opts) do
    receive do
      {^command_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        receive_result_after_down(command_ref, reason, opts)
    after
      timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor_ref, [:flush])
        File.rm(stderr_path)
        {:error, timeout_reason(opts).(command, timeout)}
    end
  end

  defp receive_result_after_down(command_ref, reason, opts) do
    receive do
      {^command_ref, result} -> result
    after
      0 -> {:error, crash_reason(opts).(reason)}
    end
  end

  defp capture([executable | args] = command, system_opts, stderr_path, opts) do
    {stdout, exit_status} =
      System.cmd(
        "/bin/sh",
        [
          "-c",
          "err=$1; shift; exec \"$@\" 2>\"$err\"",
          "lean_lsp_runtime",
          stderr_path,
          executable | args
        ],
        system_opts
      )

    {:ok,
     %{
       exit_status: exit_status,
       stderr: read_file(stderr_path),
       stdout: stdout
     }}
  rescue
    exception in [ArgumentError, ErlangError] ->
      {:error, launch_reason(opts).(command, executable, exception)}
  after
    File.rm(stderr_path)
  end

  defp timeout_reason(opts) do
    Keyword.get(opts, :timeout_reason, fn command, timeout ->
      {:command_timeout, command, timeout}
    end)
  end

  defp crash_reason(opts) do
    Keyword.get(opts, :crash_reason, fn reason -> {:command_crashed, reason} end)
  end

  defp launch_reason(opts) do
    Keyword.get(opts, :launch_reason, fn command, executable, exception ->
      {:command_launch_failed,
       %{
         command: command,
         executable: executable,
         reason: Exception.message(exception)
       }}
    end)
  end

  defp stderr_path(prefix) do
    Path.join(
      System.tmp_dir!(),
      "#{prefix}_#{System.unique_integer([:positive])}.log"
    )
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, _reason} -> ""
    end
  end
end
