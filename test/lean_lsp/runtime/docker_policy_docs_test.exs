defmodule LeanLsp.Runtime.DockerPolicyDocsTest do
  use ExUnit.Case, async: true

  test "runtime dependency policy doc covers Docker requirements and image policy" do
    doc = File.read!("docs/runtime-dependency-and-docker-policy.md")

    assert doc =~ "Docker is required"
    assert doc =~ "leanprovercommunity/lean4:latest"
    assert doc =~ "pinned tag or immutable digest"
    assert doc =~ ":docker_image"
    assert doc =~ ":image"
    assert doc =~ ":mounts"
    assert doc =~ "bind mounts"
    assert doc =~ "Docker is unavailable"
    assert doc =~ "LeanLsp.Runtime.Docker.stop/1"
  end

  test "README summarizes the Docker runtime policy and links to the detailed doc" do
    readme = File.read!("README.md")

    assert readme =~ "## Requirements"
    assert readme =~ "### Docker image policy"
    assert readme =~ "leanprovercommunity/lean4:latest"
    assert readme =~ ":docker_image"
    assert readme =~ ":container_workspace_root"
    assert readme =~ ":mounts"
    assert readme =~ "LeanLsp.Runtime.Docker.stop/1"
    assert readme =~ "docs/runtime-dependency-and-docker-policy.md"
  end

  test "Runtime.Config documents defaults, image override policy, and mount boundary" do
    {:docs_v1, _anno, _beam_language, _format, module_doc, _metadata, docs} =
      Code.fetch_docs(LeanLsp.Runtime.Config)

    rendered_docs = docs_text({module_doc, docs})

    assert rendered_docs =~ "leanprovercommunity/lean4:latest"
    assert rendered_docs =~ "convenience default"
    assert rendered_docs =~ "pinned tag or immutable digest"
    assert rendered_docs =~ ":docker_image"
    assert rendered_docs =~ "does not mount"
    assert rendered_docs =~ ":mounts"
  end

  test "Runtime.Docker documents lifecycle, mounts, cleanup, and Docker failures" do
    {:docs_v1, _anno, _beam_language, _format, module_doc, _metadata, docs} =
      Code.fetch_docs(LeanLsp.Runtime.Docker)

    rendered_docs = docs_text({module_doc, docs})

    assert rendered_docs =~ "Docker must be installed"
    assert rendered_docs =~ "leanprovercommunity/lean4:latest"
    assert rendered_docs =~ ":image"
    assert rendered_docs =~ ":mounts"
    assert rendered_docs =~ "docker stop"
    assert rendered_docs =~ "Docker is unavailable"
    assert rendered_docs =~ "{:error, reason}"
  end

  defp docs_text(docs) do
    docs
    |> inspect()
    |> String.replace("\\n", " ")
    |> String.replace(~r/\s+/, " ")
  end
end
