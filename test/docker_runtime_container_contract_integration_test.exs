defmodule LeanLsp.DockerRuntimeContainerContractIntegrationTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Config, as: RuntimeConfig
  alias LeanLsp.Runtime.Docker

  @moduletag :docker
  @moduletag :issue_72

  @docker_image_env "LEAN_LSP_TEST_DOCKER_IMAGE"
  @docker_info_timeout 15_000
  @docker_start_timeout 300_000
  @docker_exec_timeout 30_000
  @workspace_mount "/workspace"
  @test_workspace_root Path.expand("../tmp/lean_lsp_issue_72_workspaces", __DIR__)

  setup_all do
    assert_docker_available!()
    {:ok, image: lean_docker_image()}
  end

  setup do
    workspace = temporary_workspace!()
    on_exit(fn -> File.rm_rf(workspace) end)
    {:ok, workspace: workspace}
  end

  @tag timeout: @docker_start_timeout + @docker_exec_timeout + @docker_info_timeout + 5_000
  test "positive control: Docker runtime executes shell when image entrypoint is cleared", %{
    image: image,
    workspace: workspace
  } do
    runtime =
      start_public_runtime!(image, workspace, :entrypoint_cleared,
        docker_run_args: ["--entrypoint", ""]
      )

    try do
      assert_shell_exec_success!(runtime, image, :entrypoint_cleared)
    after
      stop_runtime(runtime)
    end
  end

  @tag timeout: @docker_start_timeout + @docker_exec_timeout + @docker_info_timeout + 5_000
  test "issue #72: default Docker runtime lifecycle executes a trivial shell command before Lean starts",
       %{image: image, workspace: workspace} do
    runtime = start_public_runtime!(image, workspace, :default_lifecycle)

    try do
      assert_shell_exec_success!(runtime, image, :default_lifecycle)
    after
      stop_runtime(runtime)
    end
  end

  defp lean_docker_image do
    System.get_env(@docker_image_env, RuntimeConfig.default_docker_image())
  end

  defp temporary_workspace! do
    workspace =
      Path.join(
        @test_workspace_root,
        "issue_72_#{System.system_time(:nanosecond)}_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(workspace)
    File.write!(Path.join(workspace, "lean-toolchain"), "leanprover/lean4:stable\n")
    workspace
  end

  defp start_public_runtime!(image, workspace, lifecycle_label, opts \\ []) do
    runtime_opts =
      Keyword.merge(
        [
          docker_image: image,
          container_workspace_root: @workspace_mount,
          mounts: [{workspace, @workspace_mount, "rw"}],
          start_timeout: @docker_start_timeout,
          stop_timeout: @docker_info_timeout
        ],
        opts
      )

    case LeanLsp.start_runtime(runtime_opts) do
      {:ok, runtime} ->
        runtime

      {:error, reason} ->
        flunk("""
        LeanLsp.start_runtime/1 failed before the issue #72 shell-exec reproduction command.

        This is still a Docker runtime lifecycle failure, not a Lean or Lake proof failure.
        The default lifecycle is expected to start a long-lived container that can accept
        LeanLsp.Runtime.Docker.exec/3 calls.

        lifecycle: #{lifecycle_label}
        image: #{image}
        workspace: #{workspace}
        opts: #{inspect(runtime_opts, pretty: true)}
        reason: #{inspect(reason, pretty: true)}
        """)
    end
  end

  defp assert_shell_exec_success!(runtime, image, lifecycle_label) do
    command = [
      "sh",
      "-lc",
      "printf 'lean-lsp-shell-ok\\n'; printf 'pwd=%s\\n' \"$PWD\"; printf 'toolchain='; cat lean-toolchain; printf '\\n'; uname -m"
    ]

    case Docker.exec(runtime, command, timeout: @docker_exec_timeout) do
      {:ok, %{stdout: stdout}} ->
        assert stdout =~ "lean-lsp-shell-ok"
        assert stdout =~ "pwd=#{@workspace_mount}"
        assert stdout =~ "toolchain=leanprover/lean4:stable"

      {:error, {:command_failed, %{exit_status: 137, stdout: "", stderr: ""} = failure}} ->
        flunk("""
        Reproduced issue #72: a trivial shell command was killed with exit status 137
        before Lean, Lake, or any Lean proof file was invoked.

        lifecycle: #{lifecycle_label}
        image: #{image}
        command: #{inspect(failure.command)}
        exit status: #{failure.exit_status}
        stdout: <empty>
        stderr: <empty>

        The positive-control test clears the image entrypoint and should pass on the same
        Docker host. If the positive control passes but this default-lifecycle test fails,
        focus on the Docker runtime's default image entrypoint/container-command contract.
        """)

      {:error, {:command_failed, failure}} ->
        flunk("""
        Trivial shell command failed before Lean/Lake was invoked.

        lifecycle: #{lifecycle_label}
        image: #{image}
        command: #{inspect(failure.command)}
        exit status: #{failure.exit_status}
        stdout: #{empty_as_marker(failure.stdout)}
        stderr: #{empty_as_marker(failure.stderr)}
        """)

      other ->
        flunk("""
        Trivial shell command returned an unexpected Docker runtime result before Lean/Lake was invoked.

        lifecycle: #{lifecycle_label}
        image: #{image}
        result: #{inspect(other, pretty: true)}
        """)
    end
  end

  defp assert_docker_available! do
    case DockerAvailability.executable() do
      {:ok, docker} ->
        assert_command_success!(docker, ["info"], @docker_info_timeout)

      _other ->
        flunk("Docker is not available")
    end
  end

  defp assert_command_success!(docker, args, timeout) do
    case run_command(docker, args, timeout) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {output, exit_status}} ->
        flunk("""
        Docker command failed.

        command: #{format_command(docker, args)}
        exit status: #{exit_status}
        output: #{output}
        """)

      {:exit, reason} ->
        flunk("""
        Docker command crashed.

        command: #{format_command(docker, args)}
        reason: #{inspect(reason)}
        """)

      {:timeout, timeout} ->
        flunk("""
        Docker command timed out.

        command: #{format_command(docker, args)}
        timeout: #{timeout}ms
        """)
    end
  end

  defp run_command(executable, args, timeout) do
    task = Task.async(fn -> System.cmd(executable, args, stderr_to_stdout: true) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      {:exit, reason} -> {:exit, reason}
      nil -> {:timeout, timeout}
    end
  end

  defp stop_runtime(runtime) do
    _ = Docker.stop(runtime)
    :ok
  end

  defp format_command(executable, args) do
    [executable | args]
    |> Enum.map(&inspect/1)
    |> Enum.join(" ")
  end

  defp empty_as_marker(""), do: "<empty>"
  defp empty_as_marker(output), do: output
end
