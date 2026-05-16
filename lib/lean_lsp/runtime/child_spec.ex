defmodule LeanLsp.Runtime.ChildSpec do
  @moduledoc false

  @supervisor_options [:id, :restart, :shutdown]

  @spec build(module(), keyword(), timeout()) :: Supervisor.child_spec()
  def build(module, opts, default_shutdown) when is_atom(module) and is_list(opts) do
    runtime_opts = Keyword.drop(opts, @supervisor_options)

    %{
      id: Keyword.get(opts, :id, module),
      start: {module, :start_link, [runtime_opts]},
      restart: Keyword.get(opts, :restart, :transient),
      shutdown: Keyword.get(opts, :shutdown, default_shutdown),
      type: :worker
    }
  end
end
