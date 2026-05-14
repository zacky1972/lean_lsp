defmodule LeanLsp.Runtime.DockerExecTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Docker

  describe "exec/3 acceptance" do
    setup do
      tmp_dir =
        Path.join([
          System.tmp_dir!(),
          "lean_lsp_docker_exec_test_#{System.unique_integer([:positive])}"
        ])

      bin_dir = Path.join(tmp_dir, "bin")
      File.mkdir_p!(bin_dir)

      original_path = System.get_env("PATH")
      System.put_env("PATH", bin_dir)

      write_fake_docker!(bin_dir, fake_docker_script())

      assert {:ok, runtime} =
               Docker.start_link(
                 image: "leanprovercommunity/lean4:latest",
                 container_name:
                   "lean-lsp-exec-test-#{System.unique_integer([:positive])}",
                 workdir: "/workspace",
                 start_timeout: 1_000,
                 stop_timeout: 1_000
               )

      on_exit(fn ->
        cleanup_runtime(runtime)
        restore_path(original_path)
        File.rm_rf(tmp_dir)
      end)

      {:ok, runtime: runtime}
    end

    test "returns successful output for lean --version", %{runtime: runtime} do
      assert {:ok, result} = Docker.exec(runtime, ["lean", "--version"], [])

      assert %{
               stdout: stdout,
               stderr: "",
               exit_status: 0
             } = result

      assert stdout =~ "Lean"
    end

    test "returns a structured error for a failed command", %{runtime: runtime} do
      assert {:error, {:command_failed, failure}} =
               Docker.exec(runtime, ["lean", "--definitely-invalid-option"], [])

      assert %{
               command: ["lean", "--definitely-invalid-option"],
               stdout: stdout,
               stderr: stderr,
               exit_status: exit_status
             } = failure

      assert is_binary(stdout)
      assert is_binary(stderr)
      assert exit_status > 0
      assert stderr =~ "--definitely-invalid-option"
    end
  end

  defp cleanup_runtime(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        _ = Docker.stop(pid)
        :ok
      catch
        :exit, _reason -> :ok
      end
    else
      :ok
    end
  end

  defp write_fake_docker!(bin_dir, body) do
    path = Path.join(bin_dir, "docker")

    File.write!(path, "#!/bin/sh\n" <> body)
    :ok = File.chmod(path, 0o755)

    path
  end

  defp fake_docker_script do
    """
    if [ "$1" = "version" ] && [ "$2" = "--format" ]; then
      case "$3" in
        "{{.Client.Version}}")
          echo "27.3.1"
          exit 0
          ;;
        "{{.Server.Version}}")
          echo "27.3.1"
          exit 0
          ;;
      esac
    fi

    case "$1" in
      run)
        echo "lean-lsp-test-container"
        exit 0
        ;;

      exec)
        shift

        if [ "${1:-}" = "--workdir" ]; then
          shift 2
        fi

        container_id="$1"
        shift

        case "$*" in
          "lean --version")
            echo "Lean (version 4.18.0, x86_64-unknown-linux-gnu, commit test)"
            exit 0
            ;;

          "lean --definitely-invalid-option")
            echo "lean: unrecognized option '--definitely-invalid-option'" >&2
            exit 1
            ;;
        esac

        echo "unexpected docker exec command in ${container_id}: $*" >&2
        exit 127
        ;;

      stop)
        echo "$2"
        exit 0
        ;;
    esac

    echo "unexpected docker args: $*" >&2
    exit 2
    """
  end

  defp restore_path(nil), do: System.delete_env("PATH")
  defp restore_path(path), do: System.put_env("PATH", path)
end
