defmodule LeanLsp.DockerImagePullIntegrationTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Config, as: RuntimeConfig

  @moduletag :docker

  @docker_info_timeout 15_000
  @docker_pull_timeout 300_000
  @docker_image_env "LEAN_LSP_TEST_DOCKER_IMAGE"

  @tag timeout: @docker_pull_timeout + @docker_info_timeout + 5_000
  test "configured Lean Docker image can be pulled" do
    docker = System.find_executable("docker") || flunk("docker executable was not found on PATH")
    image = lean_docker_image()

    assert_command_success!(docker, ["info"], @docker_info_timeout)
    assert_command_success!(docker, ["pull", image], @docker_pull_timeout)
  end

  defp lean_docker_image do
    System.get_env(@docker_image_env, RuntimeConfig.default_docker_image())
  end

  defp assert_command_success!(executable, args, timeout) do
    case run_command(executable, args, timeout) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {output, exit_status}} ->
        flunk("""
        command failed: #{format_command(executable, args)}

        exit status:
        #{exit_status}

        output:
        #{output}
        """)

      {:exit, reason} ->
        flunk("""
        command crashed: #{format_command(executable, args)}

        reason:
        #{inspect(reason)}
        """)

      {:timeout, timeout} ->
        flunk("""
        command timed out after #{timeout}ms: #{format_command(executable, args)}
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

  defp format_command(executable, args) do
    [executable | args]
    |> Enum.map(&inspect/1)
    |> Enum.join(" ")
  end
end
