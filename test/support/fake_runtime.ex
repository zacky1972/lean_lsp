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
