defmodule LeanLsp.Runtime.Command do
  @moduledoc false

  @typep output_result :: %{
           required(:stdout) => String.t(),
           required(:stderr) => String.t(),
           optional(atom()) => term()
         }

  @spec normalize(term()) ::
          {:ok, LeanLsp.Runtime.command()} | {:error, {:invalid_command, term()}}
  def normalize([executable | _args] = command) when is_binary(executable) do
    if executable != "" and Enum.all?(command, &is_binary/1) do
      {:ok, command}
    else
      {:error, {:invalid_command, command}}
    end
  end

  def normalize(command), do: {:error, {:invalid_command, command}}

  @spec normalize_exec_result({:ok, map()} | {:error, term()}, LeanLsp.Runtime.command()) ::
          {:ok, LeanLsp.Runtime.exec_result()} | {:error, LeanLsp.Runtime.error_reason()}
  def normalize_exec_result({:ok, %{exit_status: 0} = result}, _command) do
    {:ok, result}
  end

  def normalize_exec_result(
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

  def normalize_exec_result({:error, _reason} = error, _command), do: error

  @spec output(output_result()) :: String.t()
  def output(result) do
    [result.stdout, result.stderr]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> String.trim()
  end

  @spec call_timeout(term(), non_neg_integer()) :: timeout()
  def call_timeout(:infinity, _default), do: :infinity

  def call_timeout(timeout, _default) when is_integer(timeout) and timeout >= 0 do
    timeout + 1_000
  end

  def call_timeout(_timeout, default), do: default + 1_000
end
