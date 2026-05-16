#!/usr/bin/env sh
set -eu

if ! command -v mix >/dev/null 2>&1; then
  echo "error: mix is required to run the downstream smoke test" >&2
  exit 1
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_parent="${TMPDIR:-/tmp}"
workdir="$(mktemp -d "${tmp_parent%/}/lean_lsp_downstream_smoke.XXXXXX")"
project_dir="$workdir/downstream_smoke"

cleanup() {
  if [ "${LEAN_LSP_DOWNSTREAM_KEEP:-0}" = "1" ]; then
    printf 'Keeping downstream smoke project at %s\n' "$workdir"
  else
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT INT TERM

printf 'Creating downstream smoke project in %s\n' "$project_dir"
mix new "$project_dir" --app lean_lsp_downstream_smoke --module LeanLspDownstreamSmoke >/dev/null

cat > "$project_dir/mix.exs" <<'MIX_EXS'
defmodule LeanLspDownstreamSmoke.MixProject do
  use Mix.Project

  def project do
    [
      app: :lean_lsp_downstream_smoke,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    case System.get_env("LEAN_LSP_DOWNSTREAM_DEP", "path") do
      "path" ->
        [{:lean_lsp, path: System.fetch_env!("LEAN_LSP_DOWNSTREAM_ROOT")}]

      "hex" ->
        requirement = System.get_env("LEAN_LSP_HEX_REQUIREMENT", "~> 0.1.0")
        [{:lean_lsp, requirement}]

      other ->
        raise "unsupported LEAN_LSP_DOWNSTREAM_DEP=#{inspect(other)}; expected path or hex"
    end
  end
end
MIX_EXS

cat > "$project_dir/lib/lean_lsp_downstream_smoke.ex" <<'APP_EX'
defmodule LeanLspDownstreamSmoke do
  @moduledoc false
end
APP_EX

run_mix() {
  (cd "$project_dir" && \
    LEAN_LSP_DOWNSTREAM_ROOT="$repo_root" \
    MIX_ENV="${MIX_ENV:-prod}" \
    mix "$@")
}

printf 'Using dependency source: %s\n' "${LEAN_LSP_DOWNSTREAM_DEP:-path}"
run_mix deps.get
run_mix compile --warnings-as-errors

run_mix run -e '
{:ok, config} = LeanLsp.runtime_config([])
%LeanLsp.Runtime.Config{} = config
unless config.runtime == LeanLsp.Runtime.Docker do
  raise "unexpected default runtime: #{inspect(config.runtime)}"
end
unless is_binary(config.docker_image) and config.docker_image != "" do
  raise "expected non-empty docker image"
end
IO.puts("Downstream public API smoke check passed")
'

docker_mode="${LEAN_LSP_DOWNSTREAM_DOCKER:-auto}"
case "$docker_mode" in
  skip)
    echo "Docker runtime smoke skipped because LEAN_LSP_DOWNSTREAM_DOCKER=skip"
    ;;
  auto|required)
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      run_mix run -e '
case LeanLsp.start_runtime([]) do
  {:ok, runtime} ->
    try do
      IO.puts("Docker runtime start/stop smoke check passed")
    after
      LeanLsp.Runtime.Docker.stop(runtime)
    end

  {:error, reason} ->
    raise "Docker looked available, but LeanLsp.start_runtime/1 failed: #{inspect(reason)}"
end
'
    elif [ "$docker_mode" = "required" ]; then
      echo "error: Docker is required for this smoke run but is unavailable" >&2
      exit 1
    else
      echo "Docker unavailable; skipping optional Docker runtime smoke check"
    fi
    ;;
  *)
    echo "error: LEAN_LSP_DOWNSTREAM_DOCKER must be auto, skip, or required" >&2
    exit 1
    ;;
esac

printf 'Downstream dependency smoke test passed\n'
