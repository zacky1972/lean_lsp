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
    workspace = temporary_workspace!("minimal_lake_project")
    File.cp_r!(@minimal_lake_project_fixture, workspace)

    try do
      assert {:ok, runtime} =
               Docker.start_link(
                 image: image,
                 mounts: [{workspace, @workspace_mount}],
                 workdir: @workspace_mount,
                 start_timeout: @docker_run_timeout,
                 stop_timeout: @docker_info_timeout
               )

      try do
        pin_workspace_toolchain_to_image_default!(runtime, workspace)

        assert {:ok, %{exit_status: 0, stdout: stdout, stderr: stderr}} =
                 Docker.exec(
                   runtime,
                   ["lake", "build", "Smoke"],
                   timeout: @lake_build_timeout
                 )

        refute stdout =~ "error:"
        refute stderr =~ "error:"
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
    Path.join([
      System.tmp_dir!(),
      "lean_lsp_#{fixture_name}_#{System.unique_integer([:positive])}"
    ])
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

  defp pin_workspace_toolchain_to_image_default!(runtime, workspace) do
    toolchain = image_default_toolchain!(runtime)

    workspace
    |> Path.join("lean-toolchain")
    |> File.write!(toolchain <> "\n")
  end

  defp image_default_toolchain!(runtime) do
    assert {:ok, %{exit_status: 0, stdout: stdout, stderr: stderr}} =
             Docker.exec(
               runtime,
               ["elan", "show"],
               timeout: @docker_info_timeout,
               workdir: "/"
             )

    case active_toolchain_from_elan_show(stdout) do
      {:ok, toolchain} ->
        toolchain

      :error ->
        flunk("""
        could not determine active Lean toolchain from `elan show`.

        stdout:
        #{stdout}

        stderr:
        #{stderr}
        """)
    end
  end

  defp active_toolchain_from_elan_show(stdout) do
    lines =
      stdout
      |> String.split("\n")
      |> Enum.map(&String.trim/1)

    with {:ok, active_toolchain} <- active_toolchain_token(lines) do
      if channel_toolchain?(active_toolchain) do
        concrete_toolchain_token(lines) || {:ok, active_toolchain}
      else
        {:ok, active_toolchain}
      end
    end
  end

  defp active_toolchain_token(lines) do
    case Enum.drop_while(lines, &(&1 != "active toolchain")) do
      [] ->
        :error

      [_heading, _separator | rest] ->
        Enum.find_value(rest, :error, fn line ->
          case toolchain_token(line) do
            nil -> false
            token -> {:ok, token}
          end
        end)
    end
  end

  defp concrete_toolchain_token(lines) do
    Enum.find_value(lines, fn line ->
      case toolchain_token(line) do
        nil ->
          false

        token ->
          if concrete_toolchain?(token), do: {:ok, token}, else: false
      end
    end)
  end

  defp toolchain_token(line) do
    cond do
      line == "" ->
        nil

      String.starts_with?(line, "-") ->
        nil

      line in ["installed toolchains", "active toolchain"] ->
        nil

      String.starts_with?(line, "Lean ") ->
        nil

      true ->
        line
        |> String.split(" ", parts: 2)
        |> hd()
    end
  end

  defp channel_toolchain?(toolchain) do
    toolchain in [
      "stable",
      "nightly",
      "leanprover/lean4:stable",
      "leanprover/lean4:nightly"
    ]
  end

  defp concrete_toolchain?(toolchain) do
    Regex.match?(
      ~r/^(leanprover\/lean4:)?(v\d+\.\d+\.\d+(?:-[A-Za-z0-9._-]+)?|nightly-\d{4}-\d{2}-\d{2})$/,
      toolchain
    )
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
end
