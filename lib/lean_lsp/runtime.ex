defmodule LeanLsp.Runtime do
  @moduledoc """
  Defines the runtime behaviour used by LeanLsp consumers.

  A runtime implementation owns the execution environment needed to run Lean
  commands. Consumers use this contract to start a runtime, stop it, and execute
  commands through `exec/3` without depending on implementation-specific details.
  """

  @typedoc """
  Runtime handle returned by `start_link/1`.

  The concrete shape is implementation-specific. Consumers should pass it back to
  `exec/3` and `stop/1` instead of inspecting it.
  """
  @type t :: term()

  @typedoc """
  Runtime or execution options.

  Supported keys are implementation-specific.
  """
  @type options :: keyword()

  @typedoc """
  Command and arguments to execute in the runtime.
  """
  @type command :: [String.t()]

  @typedoc """
  Result returned by `exec/3` when a command finishes.

  The map contains captured `stdout`, captured `stderr`, and the process
  `exit_status`.
  """
  @type exec_result :: %{
          required(:stdout) => String.t(),
          required(:stderr) => String.t(),
          required(:exit_status) => non_neg_integer(),
          optional(atom()) => term()
        }

  @typedoc """
  Structured error details returned when an observed command exits non-zero.
  """
  @type command_failure :: %{
          required(:command) => command(),
          required(:stdout) => String.t(),
          required(:stderr) => String.t(),
          required(:exit_status) => pos_integer(),
          optional(atom()) => term()
        }

  @typedoc """
  Implementation-specific error reason.
  """
  @type error_reason :: term()

  @doc """
  Starts a runtime.

  Returns `{:ok, runtime}` when the runtime is ready to accept `exec/3` calls.

  Returns `{:error, reason}` when startup fails, for example because options are
  invalid or required external resources are unavailable.
  """
  @callback start_link(options()) :: {:ok, t()} | {:error, error_reason()}

  @doc """
  Stops a runtime.

  Returns `:ok` when the runtime has been stopped and cleanup has completed.

  Returns `{:error, reason}` when the runtime cannot be stopped or cleanup fails.
  """
  @callback stop(t()) :: :ok | {:error, error_reason()}

  @doc """
  Executes a command in a started runtime.

  Returns `{:ok, result}` when the command exits successfully. The result includes
  captured `stdout`, captured `stderr`, and `exit_status: 0`.

  Returns `{:error, {:command_failed, failure}}` when the command is observed but
  exits with a non-zero status. The failure map includes the original `command`,
  captured `stdout`, captured `stderr`, and the non-zero `exit_status`.

  Returns `{:error, reason}` when execution cannot be started or observed, for
  example because the runtime is unavailable, the command cannot be launched, or
  an execution failure occurs before an exit status is collected.
  """
  @callback exec(t(), command(), options()) :: {:ok, exec_result()} | {:error, error_reason()}
end
