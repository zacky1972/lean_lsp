defmodule LeanLsp.Runtime do
  @moduledoc """
  Behaviour for Lean-capable runtime implementations.

  A runtime implementation owns the external environment used to run Lean-related
  commands. The v0.1.0 public contract is intentionally small: a runtime can be
  started, stopped, and asked to execute a command.

  Consumers should depend on this behaviour when they need a test double or an
  alternate runtime implementation. Runtime implementations may have external
  side effects, such as starting an external process, executing commands through
  that process, and cleaning it up when the runtime stops.

  The callback return shapes documented here are part of the v0.1.0 preview
  contract. Implementation-specific process state, command arguments generated
  by a runtime, and undocumented error details are not stable.
  """

  @typedoc """
  Runtime handle returned by `start_link/1`.

  The concrete value is implementation-specific. Treat it as opaque and pass it
  back to `exec/3` and `stop/1` instead of inspecting it.
  """
  @type t :: term()

  @typedoc """
  Runtime or execution options.

  Supported keys are implementation-specific. Consumers should read the selected
  runtime module documentation before relying on a particular option.
  """
  @type options :: keyword()

  @typedoc """
  Command and arguments to execute in the runtime.

  Runtime implementations receive the command as a list of strings. The first
  element is the executable and the remaining elements are arguments. A runtime
  should not implicitly wrap the command in a shell unless that behavior is
  documented by the implementation.
  """
  @type command :: [String.t()]

  @typedoc """
  Result returned by `exec/3` when a command finishes successfully.

  The map contains captured `stdout`, captured `stderr`, and the process
  `exit_status`. Successful commands are expected to return `exit_status: 0`.
  """
  @type exec_result :: %{
          required(:stdout) => String.t(),
          required(:stderr) => String.t(),
          required(:exit_status) => non_neg_integer(),
          optional(atom()) => term()
        }

  @typedoc """
  Structured error details returned when an observed command exits non-zero.

  The failure contains the original `command`, captured output, and the non-zero
  `exit_status` so callers can report or inspect the command failure without
  parsing implementation-specific error text.
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

  Startup, execution, and cleanup failures may include runtime-specific details.
  Only the documented success and command-failure shapes are part of the v0.1.0
  preview contract.
  """
  @type error_reason :: term()

  @doc group: "Lifecycle callbacks"
  @doc """
  Starts a runtime and makes it ready for `exec/3` calls.

  Implementations may allocate external resources during startup, such as
  processes, containers, mounted workspaces, or temporary files. They should
  return `{:ok, runtime}` only after the runtime can accept execution requests.

  Returns `{:error, reason}` when startup fails, for example because options are
  invalid or required external resources are unavailable.
  """
  @callback start_link(options()) :: {:ok, t()} | {:error, error_reason()}

  @doc group: "Lifecycle callbacks"
  @doc """
  Stops a runtime and releases resources owned by it.

  Implementations should complete cleanup before returning `:ok`. For runtimes
  that own external resources, this is where containers, processes, mounts, or
  temporary files should be released.

  Returns `{:error, reason}` when the runtime cannot be stopped or cleanup fails.
  """
  @callback stop(t()) :: :ok | {:error, error_reason()}

  @doc group: "Execution callbacks"
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
