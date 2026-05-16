defmodule LeanLsp.Runtime.LocalTest do
  use ExUnit.Case, async: false

  alias LeanLsp.Runtime.Config
  alias LeanLsp.Runtime.Local

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "lean_lsp_local_acceptance_#{System.unique_integer([:positive])}"
      )

    workdir = Path.join(tmp_dir, "workspace")
    bin_dir = Path.join(tmp_dir, "bin")
    fixture = Path.join(bin_dir, "lean-lsp-local-fixture")

    File.mkdir_p!(workdir)
    File.mkdir_p!(bin_dir)
    File.write!(fixture, fixture_script())
    :ok = File.chmod(fixture, 0o755)

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{fixture: fixture, tmp_dir: tmp_dir, workdir: workdir}
  end

  describe "runtime contract" do
    test "exists and implements the LeanLsp.Runtime callbacks" do
      assert Code.ensure_loaded?(Local)

      for {name, arity} <- LeanLsp.Runtime.behaviour_info(:callbacks) do
        assert function_exported?(Local, name, arity),
               "expected LeanLsp.Runtime.Local to implement #{name}/#{arity}"
      end
    end

    test "can be selected through LeanLsp.start_runtime/1 and runs in the configured workdir",
         %{fixture: fixture, workdir: workdir} do
      assert {:ok, runtime} = LeanLsp.start_runtime(runtime: Local, workdir: workdir)

      on_exit(fn -> safe_stop(runtime) end)

      assert {:ok, result} = Local.exec(runtime, [fixture, "cwd"], timeout: 1_000)
      assert_same_directory(result.stdout, workdir)
      assert result.stderr == ""
      assert result.exit_status == 0
    end

    test "stop/1 can be called safely more than once", %{workdir: workdir} do
      assert {:ok, runtime} = Local.start_link(workdir: workdir)

      assert :ok = Local.stop(runtime)
      assert_safe_stop(Local.stop(runtime))
    end
  end

  describe "exec/3" do
    test "captures stdout, stderr, and zero exit status", %{fixture: fixture, workdir: workdir} do
      runtime = start_local!(workdir: workdir)

      assert {:ok, result} = Local.exec(runtime, [fixture, "emit"], timeout: 1_000)

      assert result.stdout == "stdout=ok\n"
      assert result.stderr == "stderr=ok\n"
      assert result.exit_status == 0
    end

    test "returns a structured command_failed error for non-zero exits",
         %{fixture: fixture, workdir: workdir} do
      runtime = start_local!(workdir: workdir)
      command = [fixture, "fail"]

      assert {:error, {:command_failed, failure}} = Local.exec(runtime, command, timeout: 1_000)

      assert %{
               command: ^command,
               stdout: "failure stdout\n",
               stderr: "failure stderr\n",
               exit_status: 7
             } = failure
    end

    test "passes runtime and exec environment variables to host commands",
         %{fixture: fixture, workdir: workdir} do
      runtime =
        start_local!(
          workdir: workdir,
          env: [LEAN_LSP_LOCAL_TEST_VALUE: "runtime-env"]
        )

      assert {:ok, result} = Local.exec(runtime, [fixture, "env"], timeout: 1_000)
      assert result.stdout == "runtime-env\n"

      assert {:ok, result} =
               Local.exec(runtime, [fixture, "env"],
                 env: [LEAN_LSP_LOCAL_TEST_VALUE: "exec-env"],
                 timeout: 1_000
               )

      assert result.stdout == "exec-env\n"
    end

    test "returns a structured command_timeout error and keeps the runtime usable",
         %{fixture: fixture, workdir: workdir} do
      runtime = start_local!(workdir: workdir)
      command = [fixture, "sleep"]

      assert {:error, {:command_timeout, ^command, 100}} =
               Local.exec(runtime, command, timeout: 100)

      assert {:ok, result} = Local.exec(runtime, [fixture, "emit"], timeout: 1_000)
      assert result.exit_status == 0
    end

    test "returns a structured launch error for missing executables",
         %{tmp_dir: tmp_dir, workdir: workdir} do
      runtime = start_local!(workdir: workdir)
      command = [Path.join(tmp_dir, "missing-executable"), "arg"]

      assert {:error, reason} = Local.exec(runtime, command, timeout: 1_000)
      refute match?({:command_failed, _failure}, reason)
      assert_structured_launch_error!(reason, command)
    end
  end

  describe "configuration" do
    test "accepts Local and passes host runtime options without Docker mapping",
         %{workdir: workdir} do
      assert {:ok, config} =
               Config.normalize(
                 runtime: Local,
                 workdir: workdir,
                 env: [LEAN_LSP_LOCAL_TEST_VALUE: "configured-env"],
                 timeout: 250
               )

      assert config.runtime == Local
      assert config.docker_image == Config.default_docker_image()
      assert config.container_workspace_root == Config.default_container_workspace_root()

      runtime_options = Config.to_runtime_options(config)
      assert runtime_options[:workdir] == workdir
      assert runtime_options[:env] == [LEAN_LSP_LOCAL_TEST_VALUE: "configured-env"]
      assert runtime_options[:timeout] == 250
      refute Keyword.has_key?(runtime_options, :image)
    end

    test "keeps Docker as the default runtime and preserves Docker option mapping" do
      assert {:ok, config} = Config.normalize([])

      assert config.runtime == LeanLsp.Runtime.Docker
      assert config.docker_image == Config.default_docker_image()
      assert config.container_workspace_root == Config.default_container_workspace_root()

      runtime_options = Config.to_runtime_options(config)
      assert runtime_options[:image] == Config.default_docker_image()
      assert runtime_options[:workdir] == Config.default_container_workspace_root()
    end
  end

  defp assert_same_directory(stdout, expected_workdir) do
    actual_workdir = String.trim_trailing(stdout, "\n")

    actual = File.stat!(actual_workdir)
    expected = File.stat!(expected_workdir)

    assert actual.type == :directory
    assert expected.type == :directory

    if unix_file_identity_available?(actual, expected) do
      assert {actual.major_device, actual.inode} == {expected.major_device, expected.inode}
    else
      assert Path.expand(actual_workdir) == Path.expand(expected_workdir)
    end
  end

  defp unix_file_identity_available?(actual, expected) do
    not (actual.inode in [0, :undefined]) and
      not (expected.inode in [0, :undefined]) and
      actual.major_device != :undefined and
      expected.major_device != :undefined
  end

  defp start_local!(opts) do
    assert {:ok, runtime} = Local.start_link(opts)
    on_exit(fn -> safe_stop(runtime) end)
    runtime
  end

  defp safe_stop(runtime) do
    _ignored = Local.stop(runtime)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp assert_safe_stop(:ok), do: assert(true)
  defp assert_safe_stop({:error, _reason}), do: assert(true)
  defp assert_safe_stop(other), do: flunk("expected safe stop result, got: #{inspect(other)}")

  defp assert_structured_launch_error!(reason, [executable | _] = command) do
    refute is_binary(reason),
           "expected a structured launch error, got a string: #{inspect(reason)}"

    assert term_contains?(reason, command) or term_contains?(reason, executable),
           "expected launch error to include the command or executable, got: #{inspect(reason)}"
  end

  defp term_contains?(term, expected) when term == expected, do: true

  defp term_contains?(%{} = map, expected) do
    Enum.any?(map, fn {key, value} ->
      term_contains?(key, expected) or term_contains?(value, expected)
    end)
  end

  defp term_contains?(list, expected) when is_list(list) do
    Enum.any?(list, &term_contains?(&1, expected))
  end

  defp term_contains?(tuple, expected) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&term_contains?(&1, expected))
  end

  defp term_contains?(_term, _expected), do: false

  defp fixture_script do
    [
      "#!/bin/sh\n",
      "\n",
      "case \"$1\" in\n",
      "  cwd)\n",
      "    pwd\n",
      "    ;;\n",
      "  emit)\n",
      "    printf 'stdout=ok\\n'\n",
      "    printf 'stderr=ok\\n' >&2\n",
      "    ;;\n",
      "  env)\n",
      "    printf '%s\\n' \"${LEAN_LSP_LOCAL_TEST_VALUE:-}\"\n",
      "    ;;\n",
      "  fail)\n",
      "    printf 'failure stdout\\n'\n",
      "    printf 'failure stderr\\n' >&2\n",
      "    exit 7\n",
      "    ;;\n",
      "  sleep)\n",
      "    sleep 5\n",
      "    ;;\n",
      "  *)\n",
      "    printf 'unexpected fixture command: %s\\n' \"$1\" >&2\n",
      "    exit 64\n",
      "    ;;\n",
      "esac\n"
    ]
  end
end
