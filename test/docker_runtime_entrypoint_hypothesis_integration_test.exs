defmodule LeanLsp.DockerRuntimeEntrypointHypothesisIntegrationTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Config, as: RuntimeConfig

  @moduletag :docker

  @docker_image_env "LEAN_LSP_TEST_DOCKER_IMAGE"
  @docker_run_timeout 60_000
  @docker_pull_timeout 180_000
  @docker_exec_timeout 15_000
  @docker_stop_timeout 15_000
  @workspace_mount "/workspace"
  @issue_marker "lean-lsp-issue-72-entrypoint-hypothesis-ok"

  # Keep this duplicated on purpose: this test checks the contract between the
  # current Docker runtime default keepalive command and the selected image's
  # default ENTRYPOINT/Cmd. It should be updated if the runtime default changes.
  @runtime_default_container_command [
    "sh",
    "-c",
    "trap 'exit 0' TERM INT; while true; do sleep 1; done"
  ]

  @shell_probe "printf '#{@issue_marker}\\n'; printf 'pwd=%s\\n' \"$PWD\"; uname -m"
  @exec_probe_command ["sh", "-lc", @shell_probe]

  setup_all do
    docker = System.find_executable("docker")
    assert docker, "docker executable was not found; run this test only with --include docker"

    image = System.get_env(@docker_image_env, RuntimeConfig.default_docker_image())
    image_config = ensure_image_and_read_config!(docker, image)

    {:ok, docker_executable: docker, image: image, image_config: image_config}
  end

  @tag timeout: @docker_pull_timeout + @docker_run_timeout * 2 + 20_000
  test "direct one-shot Docker run shows whether the image ENTRYPOINT changes shell semantics", %{
    docker_executable: docker,
    image: image,
    image_config: image_config
  } do
    default_entrypoint_run =
      run_one_shot_shell_probe(docker, image, [], :default_image_entrypoint)

    cleared_entrypoint_run =
      run_one_shot_shell_probe(docker, image, ["--entrypoint="], :cleared_entrypoint)

    assert_probe_success!(
      cleared_entrypoint_run,
      image,
      image_config,
      :cleared_entrypoint_one_shot
    )

    assert_default_entrypoint_discriminates!(
      default_entrypoint_run,
      cleared_entrypoint_run,
      image,
      image_config,
      :one_shot_shell_probe
    )
  end

  @tag timeout: @docker_pull_timeout + @docker_run_timeout * 2 + @docker_exec_timeout * 2 + 20_000
  test "direct long-lived Docker lifecycle shows whether ENTRYPOINT discriminates the exec probe",
       %{
         docker_executable: docker,
         image: image,
         image_config: image_config
       } do
    default_entrypoint_lifecycle =
      run_probe_through_long_lived_container(docker, image, [], :default_image_entrypoint)

    cleared_entrypoint_lifecycle =
      run_probe_through_long_lived_container(
        docker,
        image,
        ["--entrypoint="],
        :cleared_entrypoint
      )

    assert_probe_success!(
      cleared_entrypoint_lifecycle,
      image,
      image_config,
      :cleared_entrypoint_long_lived
    )

    assert_default_entrypoint_discriminates!(
      default_entrypoint_lifecycle,
      cleared_entrypoint_lifecycle,
      image,
      image_config,
      :long_lived_exec_probe
    )
  end

  @tag timeout: @docker_pull_timeout + @docker_run_timeout + 5_000
  test "selected image configuration is captured as hypothesis evidence", %{
    image: image,
    image_config: image_config
  } do
    assert image_config =~ "config="
    assert image_config =~ "os="
    assert image_config =~ "arch="

    if image == RuntimeConfig.default_docker_image() do
      assert image_config =~ "Entrypoint",
             "the default Lean image config did not expose an Entrypoint field; hypothesis evidence:\n#{image_config}"

      refute image_config =~ "\"Entrypoint\":null",
             "the default Lean image unexpectedly has no ENTRYPOINT; hypothesis evidence:\n#{image_config}"

      refute image_config =~ "\"Entrypoint\":[]",
             "the default Lean image unexpectedly has an empty ENTRYPOINT; hypothesis evidence:\n#{image_config}"
    end
  end

  defp ensure_image_and_read_config!(docker, image) do
    case image_config(docker, image) do
      {:ok, %{exit_status: 0, stdout: stdout}} ->
        stdout

      _not_present_or_uninspectable ->
        assert_command_success!(docker, ["pull", image], @docker_pull_timeout, "docker pull")

        case image_config(docker, image) do
          {:ok, %{exit_status: 0, stdout: stdout}} ->
            stdout

          {:ok, result} ->
            flunk("""
            docker image inspect failed after pulling the configured image.
            image: #{image}
            result:
            #{format_result(result)}
            """)

          other ->
            flunk("""
            docker image inspect returned an unexpected result after pulling the configured image.
            image: #{image}
            result: #{inspect(other)}
            """)
        end
    end
  end

  defp image_config(docker, image) do
    run_command(
      docker,
      [
        "image",
        "inspect",
        "--format",
        "config={{json .Config}}\nos={{.Os}}\narch={{.Architecture}}",
        image
      ],
      @docker_run_timeout
    )
  end

  defp run_one_shot_shell_probe(docker, image, docker_run_args, _lifecycle) do
    args =
      [
        "run",
        "--rm",
        "--workdir",
        @workspace_mount,
        "--volume",
        "#{File.cwd!()}:#{@workspace_mount}:rw"
      ] ++ docker_run_args ++ [image, "sh", "-lc", @shell_probe]

    run_command(docker, args, @docker_run_timeout)
  end

  defp run_probe_through_long_lived_container(docker, image, docker_run_args, lifecycle) do
    case start_long_lived_container(docker, image, docker_run_args, lifecycle) do
      {:ok, container_id} ->
        try do
          run_command(docker, ["exec", container_id | @exec_probe_command], @docker_exec_timeout)
        after
          stop_container(docker, container_id)
        end

      {:startup_failed, result} ->
        {:startup_failed, result}

      other ->
        other
    end
  end

  defp start_long_lived_container(docker, image, docker_run_args, _lifecycle) do
    cidfile =
      Path.join(
        System.tmp_dir!(),
        "lean_lsp_entrypoint_hypothesis_#{System.unique_integer([:positive])}.cid"
      )

    args =
      [
        "run",
        "--detach",
        "--rm",
        "--cidfile",
        cidfile,
        "--workdir",
        @workspace_mount,
        "--volume",
        "#{File.cwd!()}:#{@workspace_mount}:rw"
      ] ++ docker_run_args ++ [image] ++ @runtime_default_container_command

    try do
      case run_command(docker, args, @docker_run_timeout) do
        {:ok, %{exit_status: 0} = result} ->
          case File.read(cidfile) do
            {:ok, container_id} ->
              case String.trim(container_id) do
                "" ->
                  {:startup_failed,
                   %{
                     exit_status: 0,
                     stdout: result.stdout,
                     stderr: """
                     docker run --detach exited successfully, but --cidfile was empty.

                     cidfile:
                     #{cidfile}

                     run result:
                     #{format_result(result)}
                     """
                   }}

                container_id ->
                  {:ok, container_id}
              end

            {:error, reason} ->
              {:startup_failed,
               %{
                 exit_status: 0,
                 stdout: result.stdout,
                 stderr: """
                 docker run --detach exited successfully, but the --cidfile could not be read.

                 cidfile:
                 #{cidfile}

                 read error:
                 #{inspect(reason)}

                 run result:
                 #{format_result(result)}
                 """
               }}
          end

        {:ok, result} ->
          {:startup_failed, result}

        other ->
          other
      end
    after
      File.rm(cidfile)
    end
  end

  defp assert_probe_success!({:ok, %{exit_status: 0, stdout: stdout}}, _image, _config, _label) do
    assert stdout =~ @issue_marker
  end

  defp assert_probe_success!(other, image, image_config, label) do
    flunk("""
    The #{label} positive control failed.

    This does not support the ENTRYPOINT hypothesis yet, because the same Docker host,
    image, bind mount, and shell probe cannot run successfully even when the image
    ENTRYPOINT is cleared.

    image: #{image}
    image config:
    #{image_config}
    result:
    #{format_exec_result(other)}
    """)
  end

  defp assert_default_entrypoint_discriminates!(
         {:ok, %{exit_status: 0, stdout: stdout, stderr: ""}},
         _cleared_entrypoint_result,
         image,
         image_config,
         label
       ) do
    if stdout =~ @issue_marker do
      flunk("""
      The ENTRYPOINT hypothesis was not confirmed for #{label}.

      The default-image-entrypoint lifecycle and the cleared-entrypoint lifecycle both
      ran the trivial shell probe successfully. That means ENTRYPOINT is not the
      discriminator for this probe; look instead at LeanLsp command construction,
      docker exec arguments, container state, or host/runtime policy.

      image: #{image}
      image config:
      #{image_config}
      default-entrypoint stdout:
      #{stdout}
      """)
    end
  end

  defp assert_default_entrypoint_discriminates!(
         _default_entrypoint_result,
         _cleared_entrypoint_result,
         _image,
         _image_config,
         _label
       ) do
    :ok
  end

  defp assert_command_success!(docker, args, timeout, label) do
    case run_command(docker, args, timeout) do
      {:ok, %{exit_status: 0}} ->
        :ok

      {:ok, result} ->
        flunk("""
        #{label} failed.
        command: #{format_command(docker, args)}
        result:
        #{format_result(result)}
        """)

      other ->
        flunk("""
        #{label} returned an unexpected result.
        command: #{format_command(docker, args)}
        result: #{inspect(other)}
        """)
    end
  end

  defp run_command(executable, args, timeout) do
    task = Task.async(fn -> capture_command(executable, args) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:timeout, timeout}
    end
  end

  defp capture_command(executable, args) do
    command = [executable | args]

    case Enum.reject(command, &is_binary/1) do
      [] ->
        try do
          {output, exit_status} = System.cmd(executable, args, stderr_to_stdout: true)

          {:ok,
           %{
             exit_status: exit_status,
             stdout: output,
             stderr: ""
           }}
        rescue
          exception in [ArgumentError, ErlangError] ->
            {:error,
             """
             System.cmd/3 failed before Docker was invoked.

             executable:
             #{inspect(executable)}

             args:
             #{inspect(args)}

             error:
             #{Exception.message(exception)}
             """}
        end

      non_binary_args ->
        {:error,
         """
         non-binary command arguments detected before System.cmd/3.

         command:
         #{inspect(command)}

         non_binary_args:
         #{inspect(non_binary_args)}
         """}
    end
  end

  defp stop_container(docker, container_id) do
    _ = run_command(docker, ["stop", container_id], @docker_stop_timeout)
    :ok
  end

  defp format_exec_result({:ok, result}), do: format_result(result)

  defp format_exec_result({:startup_failed, result}),
    do: "startup failed:\n#{format_result(result)}"

  defp format_exec_result({:timeout, timeout}), do: "timeout after #{timeout}ms"
  defp format_exec_result({:error, reason}), do: "error: #{inspect(reason)}"
  defp format_exec_result(other), do: inspect(other)

  defp format_result(%{exit_status: exit_status, stdout: stdout, stderr: stderr}) do
    """
    exit status: #{exit_status}
    stdout:
    #{empty_as_marker(stdout)}
    stderr:
    #{empty_as_marker(stderr)}
    """
  end

  defp empty_as_marker(""), do: "<empty>"
  defp empty_as_marker(output), do: output

  defp format_command(executable, args) do
    [executable | args]
    |> Enum.map(&inspect/1)
    |> Enum.join(" ")
  end
end
