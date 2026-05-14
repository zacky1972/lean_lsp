defmodule LeanLsp.Runtime.ConfigTest do
  use ExUnit.Case, async: true

  alias LeanLsp.Runtime.Config

  describe "normalize/1" do
    test "uses documented defaults" do
      assert {:ok, config} = Config.normalize([])

      assert config.runtime == LeanLsp.Runtime.Docker
      assert config.docker_image == "leanprovercommunity/lean4:latest"
      assert config.container_workspace_root == "/workspace"

      runtime_options = Config.to_runtime_options(config)

      assert runtime_options[:image] == config.docker_image
      assert runtime_options[:workdir] == config.container_workspace_root
    end

    test "accepts an explicit runtime module and runtime options" do
      assert {:ok, config} =
               Config.normalize(
                 runtime: LeanLsp.RuntimeBehaviourTest.FakeRuntime,
                 runtime_options: [workdir: "/test-workspace", value: 1]
               )

      assert config.runtime == LeanLsp.RuntimeBehaviourTest.FakeRuntime
      assert Config.to_runtime_options(config) == [workdir: "/test-workspace", value: 1]
    end

    test "accepts explicit Docker image and container workspace root" do
      assert {:ok, config} =
               Config.normalize(
                 docker_image: "example/lean-runtime:test",
                 container_workspace_root: "/project"
               )

      runtime_options = Config.to_runtime_options(config)

      assert runtime_options[:image] == "example/lean-runtime:test"
      assert runtime_options[:workdir] == "/project"
    end

    test "passes non-config options through to runtime options" do
      assert {:ok, config} =
               Config.normalize(
                 start_timeout: 1_000,
                 runtime_options: [env: [LEANLSP_TEST: "true"]]
               )

      runtime_options = Config.to_runtime_options(config)

      assert runtime_options[:start_timeout] == 1_000
      assert runtime_options[:env] == [LEANLSP_TEST: "true"]
    end

    test "rejects invalid options" do
      assert {:error, {:invalid_option, :runtime}} =
               Config.normalize(runtime: String)

      assert {:error, {:invalid_option, :docker_image}} =
               Config.normalize(docker_image: "")

      assert {:error, {:invalid_option, :container_workspace_root}} =
               Config.normalize(container_workspace_root: "relative/path")

      assert {:error, {:invalid_option, :runtime_options}} =
               Config.normalize(runtime_options: :not_a_keyword)
    end
  end
end
