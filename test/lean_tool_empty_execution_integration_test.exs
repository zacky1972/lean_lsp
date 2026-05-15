defmodule LeanLsp.LeanToolEmptyExecutionIntegrationTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Config, as: RuntimeConfig

  @moduletag :docker

  @docker_info_timeout 15_000
  @docker_run_timeout 60_000
  @docker_image_env "LEAN_LSP_TEST_DOCKER_IMAGE"

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

  @tag timeout: @docker_run_timeout + @docker_info_timeout + 5_000
  test "configured Lean Docker image can execute lake with no arguments", %{
    image: image
  } do
    assert_bare_tool_execution!(image, "lake")
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
