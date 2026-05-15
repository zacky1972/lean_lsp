defmodule LeanLsp.LeanToolEmptyExecutionIntegrationTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Config, as: RuntimeConfig
  alias LeanLsp.Runtime.Docker

  @moduletag :docker

  @docker_info_timeout 15_000
  @docker_run_timeout 60_000
  @docker_image_env "LEAN_LSP_TEST_DOCKER_IMAGE"

  @lake_build_timeout 120_000
  @workspace_mount "/workspace"
  @minimal_lake_project_fixture Path.expand("fixtures/minimal_lake_project", __DIR__)
  @test_workspace_root Path.expand("../tmp/lean_lsp_test_workspaces", __DIR__)

  setup_all do
    assert_command_success!(["info"], @docker_info_timeout)
    {:ok, image: lean_docker_image()}
  end

  @tag timeout: @docker_run_timeout + @docker_info_timeout + 5_000
  test "configured Lean Docker image can execute lean with no arguments", %{
    image: image
  } do
    assert_bare_tool_execution!(image, "lean")
  end

  @tag timeout: @lake_build_timeout + @docker_run_timeout + @docker_info_timeout * 3 + 10_000
  test "Docker runtime can build a minimal Lake project", %{image: image} do
    workspace = prepare_minimal_lake_workspace!()

    try do
      assert {:ok, runtime} =
               Docker.start_link(
                 image: image,
                 mounts: [{workspace, @workspace_mount}],
                 workdir: @workspace_mount,
                 docker_run_args: ["--entrypoint", ""],
                 start_timeout: @docker_run_timeout,
                 stop_timeout: @docker_info_timeout
               )

      try do
        assert_workspace_visible_in_container!(runtime, image)
        assert_lake_build_smoke_success!(runtime, image)
      after
        clean_runtime_workspace(runtime)
        _ = Docker.stop(runtime)
      end
    after
      File.rm_rf(workspace)
    end
  end

  @tag timeout: @docker_run_timeout + @docker_info_timeout + 5_000
  test "configured Lean Docker image can execute lake with no arguments", %{
    image: image
  } do
    assert_bare_tool_execution!(image, "lake")
  end

  defp temporary_workspace!(fixture_name) do
    workspace =
      Path.join(
        @test_workspace_root,
        "#{fixture_name}_#{System.system_time(:nanosecond)}_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(workspace)
    workspace
  end

  defp clean_runtime_workspace(runtime) do
    _ =
      Docker.exec(
        runtime,
        ["sh", "-c", "rm -rf /workspace/.lake /workspace/lake-manifest.json"],
        timeout: @docker_info_timeout
      )

    :ok
  end

  defp lean_docker_image do
    System.get_env(@docker_image_env, RuntimeConfig.default_docker_image())
  end

  defp assert_bare_tool_execution!(image, tool) do
    args = ["run", "--rm", "--entrypoint", "", image, tool]
    assert_command_success!(args, @docker_info_timeout)
  end

  defp assert_command_success!(args, timeout) do
    case DockerAvailability.executable() do
      {:ok, docker} ->
        case run_command(docker, args, timeout) do
          {:ok, {_output, exit_status}} when exit_status in 0..124 ->
            :ok

          {:ok, {output, exit_status}} ->
            flunk("""
            container command failed: #{format_command(docker, args)}

            exit status:
            #{exit_status}

            output:
            #{output}
            """)

          {:exit, reason} ->
            flunk("""
            container command crashed: #{format_command(docker, args)}

            reason:
            #{inspect(reason)}
            """)

          {:timeout, timeout} ->
            flunk("""
            container command timed out after #{timeout}ms: #{format_command(docker, args)}
            """)
        end

      _ ->
        flunk("""
        docker not found.
        """)
    end
  end

  defp run_command(executable, args, timeout) do
    task =
      Task.async(fn ->
        System.cmd(executable, args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      {:exit, reason} -> {:exit, reason}
      nil -> {:timeout, timeout}
    end
  end

  defp format_command(executable, args) do
    [executable | args]
    |> Enum.map(&inspect/1)
    |> Enum.join(" ")
  end

  defp remove_project_toolchain_override!(workspace) do
    toolchain_path = Path.join(workspace, "lean-toolchain")

    case File.rm(toolchain_path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        flunk("""
        could not remove fixture lean-toolchain from copied workspace.

        path:
        #{toolchain_path}

        reason:
        #{inspect(reason)}
        """)
    end
  end

  defp assert_lake_build_smoke_success!(runtime, image) do
    case Docker.exec(
           runtime,
           ["lake", "build", "Smoke"],
           timeout: @lake_build_timeout
         ) do
      {:ok, %{exit_status: 0, stdout: stdout, stderr: stderr}} ->
        refute stdout =~ "error:"
        refute stderr =~ "error:"

      {:error, {:command_failed, %{exit_status: 137, stdout: "", stderr: ""} = failure}} ->
        flunk("""
        minimal Lake project build was killed with exit status 137 and empty stdout/stderr.

        LeanLsp.Runtime.Docker did preserve the observed command failure, but this Docker
        acceptance test requires the configured Lean image to be able to compile a tiny
        Lake project.

        image:
        #{image}

        command:
        #{inspect(failure.command)}

        exit status:
        #{failure.exit_status}

        stdout:
        <empty>

        stderr:
        <empty>
        """)

      {:error, {:command_failed, failure}} ->
        flunk("""
        minimal Lake project build failed.

        image:
        #{image}

        command:
        #{inspect(failure.command)}

        exit status:
        #{failure.exit_status}

        stdout:
        #{empty_as_marker(failure.stdout)}

        stderr:
        #{empty_as_marker(failure.stderr)}
        """)

      other ->
        flunk("""
        minimal Lake project build returned an unexpected result.

        image:
        #{image}

        result:
        #{inspect(other)}
        """)
    end
  end

  defp empty_as_marker(""), do: "<empty>"
  defp empty_as_marker(output), do: output

  defp prepare_minimal_lake_workspace! do
    workspace = temporary_workspace!("minimal_lake_project")

    copy_fixture_contents!(@minimal_lake_project_fixture, workspace)

    # Keep the checked-in fixture self-contained, but avoid forcing this
    # Docker boundary test through elan's project-specific toolchain resolution.
    remove_project_toolchain_override!(workspace)

    assert_required_fixture_files!(workspace)

    workspace
  end

  defp copy_fixture_contents!(fixture_dir, workspace) do
    assert File.dir?(fixture_dir), "missing fixture directory: #{fixture_dir}"

    fixture_dir
    |> File.ls!()
    |> Enum.each(fn entry ->
      File.cp_r!(
        Path.join(fixture_dir, entry),
        Path.join(workspace, entry)
      )
    end)

    :ok
  end

  defp assert_required_fixture_files!(workspace) do
    for relative_path <- ["lakefile.lean", "Smoke.lean"] do
      path = Path.join(workspace, relative_path)

      assert File.exists?(path), """
      fixture file is missing before Docker mount.

      expected:
      #{path}

      workspace:
      #{workspace}

      workspace entries:
      #{workspace_listing(workspace)}
      """
    end

    :ok
  end

  defp workspace_listing(workspace) do
    workspace
    |> File.ls!()
    |> Enum.sort()
    |> Enum.join("\n")
  end

  defp assert_workspace_visible_in_container!(runtime, image) do
    command = [
      "sh",
      "-c",
      "pwd; echo '-- workspace files --'; ls -la; test -f lakefile.lean && test -f Smoke.lean"
    ]

    case Docker.exec(runtime, command, timeout: @docker_info_timeout) do
      {:ok, %{exit_status: 0, stdout: stdout, stderr: stderr}} ->
        assert stdout =~ @workspace_mount
        refute stderr =~ "No such file"

        :ok

      {:error, {:command_failed, failure}} ->
        flunk("""
        minimal Lake project fixture is not visible in the Docker workspace.

        This means the test has not reached the `lake build Smoke` boundary yet.
        Check the host workspace copy and Docker bind mount.

        image:
        #{image}

        command:
        #{inspect(failure.command)}

        exit status:
        #{failure.exit_status}

        stdout:
        #{empty_as_marker(failure.stdout)}

        stderr:
        #{empty_as_marker(failure.stderr)}
        """)

      other ->
        flunk("""
        Docker workspace visibility check returned an unexpected result.

        image:
        #{image}

        result:
        #{inspect(other)}
        """)
    end
  end
end
