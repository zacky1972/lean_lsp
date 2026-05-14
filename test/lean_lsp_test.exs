defmodule LeanLspTest do
  use ExUnit.Case, async: true

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
end
