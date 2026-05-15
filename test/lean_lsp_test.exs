defmodule LeanLspTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Docker

  doctest LeanLsp

  test "starts the configured runtime module without changing application code" do
    assert {:ok, runtime} =
             LeanLsp.start_runtime(
               runtime: LeanLsp.RuntimeBehaviourTest.FakeRuntime,
               runtime_options: [workdir: "/configured-test-workspace"]
             )

    assert runtime.runtime == LeanLsp.RuntimeBehaviourTest.FakeRuntime
    assert runtime.opts == [workdir: "/configured-test-workspace"]
  end

  test "exposes normalized runtime configuration" do
    assert {:ok, config} =
             LeanLsp.runtime_config(
               docker_image: "example/lean-runtime:test",
               container_workspace_root: "/configured-workspace"
             )

    assert config.runtime == LeanLsp.Runtime.Docker
    assert config.docker_image == "example/lean-runtime:test"
    assert config.container_workspace_root == "/configured-workspace"
  end

  test "Docker runtime preserves docker exec exit status 137 with empty output" do
    tmp_dir =
      Path.join([
        System.tmp_dir!(),
        "lean_lsp_fake_docker_#{System.unique_integer([:positive])}"
      ])

    bin_dir = Path.join(tmp_dir, "bin")
    log_file = Path.join(tmp_dir, "docker_calls.log")

    File.mkdir_p!(bin_dir)

    original_path = System.get_env("PATH")
    put_fake_docker_path!(bin_dir, original_path)

    on_exit(fn ->
      restore_path!(original_path)
      File.rm_rf(tmp_dir)
    end)

    write_fake_docker!(bin_dir, fake_docker_runtime_script(log_file))

    assert {:ok, runtime} =
             Docker.start_link(
               image: "fake-lean-image:latest",
               workdir: "/workspace",
               start_timeout: 1_000,
               stop_timeout: 1_000
             )

    try do
      assert {:error, {:command_failed, failure}} =
               Docker.exec(
                 runtime,
                 ["lake", "build", "DockerAvailability"],
                 timeout: 1_000
               )

      assert Map.take(failure, [:command, :exit_status, :stdout, :stderr]) == %{
               command: ["lake", "build", "DockerAvailability"],
               exit_status: 137,
               stdout: "",
               stderr: ""
             }

      assert File.read!(log_file) =~
               "exec --workdir /workspace lean-lsp-test-container lake build DockerAvailability\n"
    after
      _ = Docker.stop(runtime)
    end
  end

  defp put_fake_docker_path!(bin_dir, nil), do: System.put_env("PATH", bin_dir)
  defp put_fake_docker_path!(bin_dir, ""), do: System.put_env("PATH", bin_dir)

  defp put_fake_docker_path!(bin_dir, original_path) do
    System.put_env("PATH", bin_dir <> ":" <> original_path)
  end

  defp restore_path!(nil), do: System.delete_env("PATH")
  defp restore_path!(""), do: System.put_env("PATH", "")
  defp restore_path!(original_path), do: System.put_env("PATH", original_path)

  defp write_fake_docker!(bin_dir, body) do
    path = Path.join(bin_dir, "docker")

    File.write!(path, "#!/bin/sh\n" <> body)
    :ok = File.chmod(path, 0o755)

    path
  end

  defp fake_docker_runtime_script(log_file) do
    """
    echo "$*" >> #{sh_quote(log_file)}

    if [ "$1" = "version" ] && [ "$2" = "--format" ]; then
      case "$3" in
        "{{.Client.Version}}") echo "27.3.1"; exit 0 ;;
        "{{.Server.Version}}") echo "27.3.1"; exit 0 ;;
      esac
    fi

    case "$1" in
      run)
        echo "lean-lsp-test-container"
        exit 0
        ;;

      exec)
        shift

        while [ $# -gt 0 ]; do
          case "$1" in
            --workdir|--env)
              shift 2
              ;;
            *)
              break
              ;;
          esac
        done

        container="$1"
        shift

        if [ "$container" = "lean-lsp-test-container" ] &&
           [ "$1" = "lake" ] &&
           [ "$2" = "build" ] &&
           [ "$3" = "DockerAvailability" ]; then
          exit 137
        fi

        echo "unexpected docker exec payload: $*" >&2
        exit 2
        ;;

      stop)
        exit 0
        ;;
    esac

    echo "unexpected docker args: $*" >&2
    exit 2
    """
  end

  defp sh_quote(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
