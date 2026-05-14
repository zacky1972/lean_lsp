defmodule LeanLsp.Runtime.DockerLifecycleTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Docker

  @container_id "lean-lsp-container-123"
  @container_name "lean-lsp-runtime-test"
  @image "leanprovercommunity/lean4:test"

  setup do
    tmp_dir =
      Path.join([
        System.tmp_dir!(),
        "lean_lsp_docker_lifecycle_test_#{System.unique_integer([:positive])}"
      ])

    bin_dir = Path.join(tmp_dir, "bin")
    calls_log = Path.join(tmp_dir, "docker_calls.log")
    container_state = Path.join(tmp_dir, "containers.state")

    File.mkdir_p!(bin_dir)
    File.write!(calls_log, "")
    File.write!(container_state, "")

    original_path = System.get_env("PATH")
    System.put_env("PATH", bin_dir)

    on_exit(fn ->
      restore_env("PATH", original_path)
      File.rm_rf(tmp_dir)
    end)

    {:ok, bin_dir: bin_dir, calls_log: calls_log, container_state: container_state}
  end

  describe "container lifecycle" do
    test "runtime startup and normal shutdown leave no dangling containers", context do
      write_fake_docker!(context, successful_lifecycle_script(context))

      assert {:ok, runtime} =
               Docker.start_link(
                 container_name: @container_name,
                 image: @image
               )

      assert :ok = Docker.stop(runtime)

      calls = docker_calls(context.calls_log)

      run_call = Enum.find(calls, &String.starts_with?(&1, "run "))
      stop_call = Enum.find(calls, &String.starts_with?(&1, "stop "))

      assert run_call
      assert stop_call

      assert run_call =~ "run --detach"
      assert run_call =~ " --rm"
      assert run_call =~ "--name #{@container_name}"
      assert run_call =~ @image

      assert stop_call == "stop #{@container_id}"

      assert File.read!(context.container_state) == ""
    end

    test "container identity is kept in runtime state for debugging", context do
      write_fake_docker!(context, successful_lifecycle_script(context))

      assert {:ok, runtime} =
               Docker.start_link(
                 container_name: @container_name,
                 image: @image
               )

      on_exit(fn -> stop_if_alive(runtime) end)

      assert %Docker{} = state = :sys.get_state(runtime)
      assert state.container_id == @container_id
      assert state.container_name == @container_name
      assert state.image == @image

      assert :ok = Docker.stop(runtime)
    end

    test "startup failures are returned as observable error tuples", context do
      write_fake_docker!(context, failing_run_script(context))

      assert {:error, {:docker_command_failed, args, 42, output}} =
               Docker.start_link(
                 container_name: @container_name,
                 image: @image
               )

      assert ["run", "--detach", "--rm" | _] = args
      assert "--name" in args
      assert @container_name in args
      assert @image in args

      assert output =~ "run stdout"
      assert output =~ "cannot start container"

      refute Enum.any?(docker_calls(context.calls_log), &String.starts_with?(&1, "stop "))
      assert File.read!(context.container_state) == ""
    end
  end

  defp successful_lifecycle_script(%{calls_log: calls_log, container_state: container_state}) do
    """
    CALLS_LOG=#{sh_quote(calls_log)}
    CONTAINER_STATE=#{sh_quote(container_state)}
    CONTAINER_ID=#{sh_quote(@container_id)}

    echo "$*" >> "$CALLS_LOG"

    if [ "$1" = "version" ] && [ "$2" = "--format" ]; then
      case "$3" in
        "{{.Client.Version}}") echo "27.3.1"; exit 0 ;;
        "{{.Server.Version}}") echo "27.3.2"; exit 0 ;;
      esac
    fi

    case "$1" in
      run)
        auto_remove=0
        detached=0
        name=""
        previous=""

        for arg in "$@"; do
          if [ "$arg" = "--rm" ]; then
            auto_remove=1
          fi

          if [ "$arg" = "--detach" ]; then
            detached=1
          fi

          if [ "$previous" = "--name" ]; then
            name="$arg"
          fi

          previous="$arg"
        done

        printf "container_id=%s\\nauto_remove=%s\\ndetached=%s\\nname=%s\\n" \
          "$CONTAINER_ID" "$auto_remove" "$detached" "$name" > "$CONTAINER_STATE"

        printf "%s\\n" "$CONTAINER_ID"
        exit 0
        ;;

      stop)
        auto_remove=0

        if [ -f "$CONTAINER_STATE" ]; then
          . "$CONTAINER_STATE"
        fi

        if [ "$2" = "$CONTAINER_ID" ]; then
          if [ "$auto_remove" = "1" ]; then
            : > "$CONTAINER_STATE"
          fi

          printf "%s\\n" "$CONTAINER_ID"
          exit 0
        fi

        echo "No such container: $2" >&2
        exit 1
        ;;

      rm)
        if [ "$2" = "$CONTAINER_ID" ]; then
          : > "$CONTAINER_STATE"
          printf "%s\\n" "$CONTAINER_ID"
          exit 0
        fi

        echo "No such container: $2" >&2
        exit 1
        ;;
    esac

    echo "unexpected docker args: $*" >&2
    exit 2
    """
  end

  defp failing_run_script(%{calls_log: calls_log}) do
    """
    CALLS_LOG=#{sh_quote(calls_log)}

    echo "$*" >> "$CALLS_LOG"

    if [ "$1" = "version" ] && [ "$2" = "--format" ]; then
      case "$3" in
        "{{.Client.Version}}") echo "27.3.1"; exit 0 ;;
        "{{.Server.Version}}") echo "27.3.2"; exit 0 ;;
      esac
    fi

    case "$1" in
      run)
        echo "run stdout"
        echo "cannot start container" >&2
        exit 42
        ;;
    esac

    echo "unexpected docker args: $*" >&2
    exit 2
    """
  end

  defp write_fake_docker!(%{bin_dir: bin_dir}, body) do
    path = Path.join(bin_dir, "docker")

    File.write!(path, "#!/bin/sh\n" <> body)
    :ok = File.chmod(path, 0o755)

    path
  end

  defp docker_calls(calls_log) do
    calls_log
    |> File.read!()
    |> String.split("\n", trim: true)
  end

  defp stop_if_alive(runtime) when is_pid(runtime) do
    if Process.alive?(runtime) do
      _ignored = Docker.stop(runtime)
    end

    :ok
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp sh_quote(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
