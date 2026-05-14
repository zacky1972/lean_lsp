defmodule LeanLsp.Runtime.DockerTest do
  use ExUnit.Case, async: true

  @moduletag :docker

  @image "lean-lsp-runtime-docker-acceptance:issue-7"

  @identity_keys [
    :container_id,
    :container_name,
    :container,
    :docker_container,
    :id,
    :name
  ]

  if DockerAvailability.available?() do
    setup_all do
      remove_containers_for_image(@image)
      build_acceptance_image!(@image)

      on_exit(fn ->
        remove_containers_for_image(@image)
        docker(["image", "rm", "-f", @image])
      end)

      :ok
    end
  else
    @moduletag skip: "Docker is not available to the current process"
  end

  describe "LeanLsp.Runtime.Docker contract" do
    test "exists and implements the runtime behaviour callbacks" do
      assert Code.ensure_loaded?(LeanLsp.Runtime.Docker)

      for {name, arity} <- LeanLsp.Runtime.behaviour_info(:callbacks) do
        assert function_exported?(LeanLsp.Runtime.Docker, name, arity),
               "expected LeanLsp.Runtime.Docker to implement #{name}/#{arity}"
      end
    end

    test "keeps Docker implementation details out of non-Docker runtime modules" do
      lib_dir = Path.expand("../../../lib", __DIR__)
      docker_runtime_path = Path.join(lib_dir, "lean_lsp/runtime/docker.ex")

      docker_detail_pattern =
        ~r/System\.cmd\([^)]*["']docker["']|Port\.open\([^)]*docker|docker\s+(run|create|start|stop|rm|exec|inspect)|--name|--rm|container_id|container_name/

      lib_dir
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&(&1 == docker_runtime_path))
      |> Enum.each(fn path ->
        source = File.read!(path)

        refute source =~ docker_detail_pattern,
               "expected Docker-specific implementation details to stay out of #{Path.relative_to_cwd(path)}"
      end)
    end
  end

  describe "start_link/1" do
    test "starts a runtime process from the configured Docker image and tracks container identity" do
      assert {:ok, pid} = LeanLsp.Runtime.Docker.start_link(image: @image)

      on_exit(fn -> cleanup_runtime(pid) end)

      assert is_pid(pid)
      assert Process.alive?(pid)

      identity = assert_container_identity!(pid)

      assert_container_running!(identity)
      assert docker_inspect!(identity, "{{.Config.Image}}") == @image
    end

    test "can be started under a supervisor" do
      pid = start_supervised!({LeanLsp.Runtime.Docker, image: @image})

      assert is_pid(pid)
      assert Process.alive?(pid)

      identity = assert_container_identity!(pid)

      assert_container_running!(identity)
    end

    test "uses the configured Docker image and container workspace root" do
      workspace_root = "/configured-workspace"

      assert {:ok, pid} =
               LeanLsp.Runtime.Docker.start_link(
                 image: @image,
                 container_workspace_root: workspace_root
               )

      on_exit(fn -> cleanup_runtime(pid) end)

      identity = assert_container_identity!(pid)

      assert docker_inspect!(identity, "{{.Config.Image}}") == @image
      assert docker_inspect!(identity, "{{.Config.WorkingDir}}") == workspace_root

      assert {:ok, result} =
               LeanLsp.Runtime.Docker.exec(pid, ["pwd"], timeout: 5_000)

      assert String.trim(result.stdout) == workspace_root
    end
  end

  describe "exec/3" do
    test "executes a command in the backing container and captures stdout" do
      assert {:ok, pid} = LeanLsp.Runtime.Docker.start_link(image: @image)

      on_exit(fn -> cleanup_runtime(pid) end)

      assert {:ok, result} =
               LeanLsp.Runtime.Docker.exec(
                 pid,
                 ["sh", "-c", "printf 'ok\n'"],
                 timeout: 5_000
               )

      assert result.stdout == "ok\n"
      assert result.stderr == ""
      assert result.exit_status == 0
    end

    test "returns a structured error and keeps the runtime alive when a command exits non-zero" do
      assert {:ok, pid} = LeanLsp.Runtime.Docker.start_link(image: @image)
      on_exit(fn -> cleanup_runtime(pid) end)

      command = ["sh", "-c", "echo boom >&2; exit 7"]

      assert {:error, {:command_failed, failure}} =
               LeanLsp.Runtime.Docker.exec(
                 pid,
                 command,
                 timeout: 5_000
               )

      assert %{
               command: ^command,
               stdout: "",
               stderr: stderr,
               exit_status: 7
             } = failure

      assert String.trim(stderr) == "boom"
      assert Process.alive?(pid)
    end
  end

  describe "stop/1" do
    test "stops the runtime process and the backing container cleanly" do
      assert {:ok, pid} = LeanLsp.Runtime.Docker.start_link(image: @image)

      on_exit(fn -> cleanup_runtime(pid) end)

      identity = assert_container_identity!(pid)

      assert_container_running!(identity)

      assert :ok = LeanLsp.Runtime.Docker.stop(pid)

      refute Process.alive?(pid)

      assert_eventually(
        fn -> not container_running?(identity) end,
        "expected Docker container #{identity} to stop after LeanLsp.Runtime.Docker.stop/1"
      )
    end
  end

  defp build_acceptance_image!(image) do
    build_dir =
      Path.join(
        System.tmp_dir!(),
        "lean_lsp_docker_acceptance_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(build_dir)

    dockerfile = """
    FROM busybox:1.36.1
    CMD ["sh", "-c", "trap 'exit 0' TERM INT; while true; do sleep 1; done"]
    """

    File.write!(Path.join(build_dir, "Dockerfile"), dockerfile)

    try do
      docker!(["build", "-t", image, build_dir])
    after
      File.rm_rf!(build_dir)
    end
  end

  defp assert_container_identity!(pid) do
    state = :sys.get_state(pid)

    identity =
      state
      |> container_identity_candidates()
      |> Enum.uniq()
      |> Enum.find(&container_exists?/1)

    assert is_binary(identity) and identity != "",
           "expected runtime state to contain a Docker container id or name, got: #{inspect(state)}"

    identity
  end

  defp container_identity_candidates(%{} = map) do
    direct =
      for key <- @identity_keys,
          value = Map.get(map, key),
          is_binary(value),
          value != "" do
        value
      end

    nested =
      map
      |> Map.drop([:__struct__])
      |> Map.values()
      |> Enum.flat_map(&container_identity_candidates/1)

    direct ++ nested
  end

  defp container_identity_candidates({key, value}) do
    direct =
      if key in @identity_keys and is_binary(value) and value != "" do
        [value]
      else
        []
      end

    direct ++ container_identity_candidates(value)
  end

  defp container_identity_candidates(list) when is_list(list) do
    Enum.flat_map(list, &container_identity_candidates/1)
  end

  defp container_identity_candidates(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&container_identity_candidates/1)
  end

  defp container_identity_candidates(_other), do: []

  defp assert_container_running!(identity) do
    assert_eventually(
      fn -> container_running?(identity) end,
      "expected Docker container #{identity} to be running"
    )
  end

  defp container_exists?(identity) when is_binary(identity) and identity != "" do
    {_output, status} = docker(["inspect", "--type", "container", identity])

    status == 0
  end

  defp container_exists?(_identity), do: false

  defp container_running?(identity) do
    case docker(["inspect", "--type", "container", "-f", "{{.State.Running}}", identity]) do
      {"true\n", 0} -> true
      {"true", 0} -> true
      _other -> false
    end
  end

  defp docker_inspect!(identity, format) do
    docker!(["inspect", "--type", "container", "-f", format, identity])
  end

  defp cleanup_runtime(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        LeanLsp.Runtime.Docker.stop(pid)
      catch
        :exit, _reason -> :ok
      end
    end
  end

  defp remove_containers_for_image(image) do
    case docker(["ps", "-aq", "--filter", "ancestor=#{image}"]) do
      {output, 0} ->
        output
        |> String.split()
        |> Enum.each(fn id -> docker(["rm", "-f", id]) end)

      _other ->
        :ok
    end
  end

  defp assert_eventually(fun, message, attempts \\ 20)

  defp assert_eventually(fun, message, 0) do
    assert fun.(), message
  end

  defp assert_eventually(fun, message, attempts) do
    if fun.() do
      assert true
    else
      Process.sleep(100)
      assert_eventually(fun, message, attempts - 1)
    end
  end

  defp docker!(args) do
    {output, status} = docker(args)

    assert status == 0, """
    expected docker #{Enum.join(args, " ")} to succeed

    #{output}
    """

    String.trim(output)
  end

  defp docker(args) do
    case DockerAvailability.executable() do
      {:ok, docker} ->
        System.cmd(docker, args, stderr_to_stdout: true)

      {:error, reason} ->
        {inspect(reason), 127}
    end
  end
end
