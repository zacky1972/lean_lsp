defmodule LeanLsp.RuntimeBehaviourTest do
  use ExUnit.Case, async: true

  describe "LeanLsp.Runtime behaviour" do
    test "defines the callback contract required by runtime consumers" do
      assert Code.ensure_loaded?(LeanLsp.Runtime)

      callbacks =
        LeanLsp.Runtime.behaviour_info(:callbacks)
        |> Enum.sort()

      assert {:start_link, 1} in callbacks
      assert {:stop, 1} in callbacks
      assert {:exec, 3} in callbacks
    end

    test "allows consumers to depend on the runtime behaviour without depending on Docker" do
      assert Code.ensure_loaded?(LeanLsp.Runtime)

      assert {:module, _module, _binary, _term} =
               defmodule LeanLsp.RuntimeBehaviourTest.FakeRuntime do
                 @behaviour LeanLsp.Runtime

                 @impl true
                 def start_link(opts) when is_list(opts) do
                   {:ok, %{runtime: __MODULE__, opts: opts}}
                 end

                 @impl true
                 def stop(_runtime) do
                   :ok
                 end

                 @impl true
                 def exec(runtime, command, opts)
                     when is_list(command) and is_list(opts) do
                   {:ok,
                    %{
                      runtime: runtime,
                      command: command,
                      stdout: "ok\n",
                      stderr: "",
                      exit_status: 0
                    }}
                 end
               end

      runtime_module = LeanLsp.RuntimeBehaviourTest.FakeRuntime

      assert {:ok, runtime} = runtime_module.start_link(workdir: "/workspace")

      assert {:ok, result} =
               runtime_module.exec(runtime, ["lean", "--version"], timeout: 5_000)

      assert result.stdout == "ok\n"
      assert result.stderr == ""
      assert result.exit_status == 0

      assert :ok = runtime_module.stop(runtime)
    end

    test "documents expected return values and failure modes" do
      assert {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, docs} =
               Code.fetch_docs(LeanLsp.Runtime)

      assert_doc_contains(moduledoc, [
        "runtime",
        "start",
        "stop",
        "exec"
      ])

      refute moduledoc =~ "LeanLsp.Runtime.Docker"

      assert_callback_doc_contains(docs, :start_link, 1, [
        "{:ok",
        "{:error"
      ])

      assert_callback_doc_contains(docs, :stop, 1, [
        ":ok",
        "{:error"
      ])

      assert_callback_doc_contains(docs, :exec, 3, [
        "{:ok",
        "{:error",
        "stdout",
        "stderr",
        "exit"
      ])
    end
  end

  defp assert_callback_doc_contains(docs, name, arity, required_fragments) do
    doc =
      Enum.find_value(docs, fn
        {{:callback, ^name, ^arity}, _anno, _signature, %{"en" => doc}, _metadata} ->
          doc

        _other ->
          nil
      end)

    assert is_binary(doc), "expected @doc for callback #{name}/#{arity}"

    assert_doc_contains(doc, required_fragments)
  end

  defp assert_doc_contains(doc, required_fragments) when is_binary(doc) do
    normalized_doc = String.downcase(doc)

    for fragment <- required_fragments do
      assert normalized_doc =~ String.downcase(fragment),
             "expected documentation to contain #{inspect(fragment)}"
    end
  end
end
