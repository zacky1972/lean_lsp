# Runtime dependency and Docker/local runtime policy

LeanLsp v0.2.1 exposes a Lean-capable runtime preview with two runtime implementations:

- `LeanLsp.Runtime.Docker`
- `LeanLsp.Runtime.Local`

Docker remains the default runtime. The local runtime is available for host-backed development workflows.

Users can install and inspect configuration without Docker. Starting the default runtime requires Docker. Starting the local runtime requires the selected host executable to be available in the process environment.

## Runtime selection

The default runtime is Docker-backed:

```elixir
{:ok, config} = LeanLsp.runtime_config()

%LeanLsp.Runtime.Config{
  runtime: LeanLsp.Runtime.Docker
} = config
```

Callers can explicitly select the local runtime:

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    runtime: LeanLsp.Runtime.Local,
    workdir: File.cwd!()
  )
```

The local runtime does not require Docker-specific options such as `:docker_image`.

## External runtime requirements

Docker is required for the default runtime path:

- `LeanLsp.runtime_config/1` validates and normalizes options without starting Docker.
- `LeanLsp.start_runtime/1` starts `LeanLsp.Runtime.Docker` by default and needs a reachable Docker executable.
- The calling environment must have permission to run Docker containers.
- The selected image must be available locally or pullable by Docker.

A local Lean installation on the host is not required for the Docker runtime path.

For the local runtime path:

- Docker is not required.
- The selected command is executed on the host.
- Lean, Lake, Elan, or any other executable used by the caller must already be installed and reachable from the BEAM process environment.
- The caller is responsible for choosing a working directory appropriate for the command.

## Default Docker image policy

The v0.2.1 preview default image is:

```text
leanprovercommunity/lean4:latest
```

The package keeps `latest` as a convenience default for the runtime preview so users can try the Docker runtime without choosing an image up front.

This is a convenience default, not a reproducibility guarantee.

For reproducible workflows, pass a pinned tag or immutable digest explicitly with the public `:docker_image` option:

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    docker_image: "leanprovercommunity/lean4:<pinned-tag-or-digest>"
  )
```

When calling `LeanLsp.Runtime.Docker.start_link/1` directly, use the runtime `:image` option name:

```elixir
{:ok, runtime} =
  LeanLsp.Runtime.Docker.start_link(
    image: "leanprovercommunity/lean4:<pinned-tag-or-digest>"
  )
```

## Docker workspace and mount behaviour

`:container_workspace_root` configures the working directory inside the container.

It does not automatically mount a host directory. Host filesystem access is opt-in through the runtime-specific `:mounts` option:

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    container_workspace_root: "/workspace",
    mounts: [{File.cwd!(), "/workspace", "ro"}]
  )
```

Docker bind mounts can expose host files to the container. Use read-only mounts such as `"ro"` when the runtime only needs to read project files.

## Local runtime working directory behaviour

The local runtime executes host commands from the configured working directory.

Example:

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    runtime: LeanLsp.Runtime.Local,
    workdir: File.cwd!()
  )

try do
  {:ok, result} =
    LeanLsp.Runtime.Local.exec(runtime, ["lake", "--version"], timeout: 120_000)

  IO.puts(result.stdout)
after
  LeanLsp.Runtime.Local.stop(runtime)
end
```

The local runtime does not create an isolated filesystem. Commands run with access to the host environment visible to the BEAM process, subject to the configured working directory and environment options.

## Environment variables

Runtime implementations may support environment variables through runtime-specific options and per-command execution options.

Callers should pass only the environment variables required by the runtime command.

For Docker runtime execution, environment variables are converted to Docker CLI arguments.

For local runtime execution, environment variables are passed to the host process.

## Container lifecycle and cleanup

`LeanLsp.start_runtime/1` starts a long-lived Docker container when the Docker runtime is selected.

The returned runtime handle is opaque and should be passed to `LeanLsp.Runtime.Docker.exec/3` and `LeanLsp.Runtime.Docker.stop/1`.

Callers that start the Docker runtime directly are responsible for stopping it:

```elixir
{:ok, runtime} = LeanLsp.start_runtime()

try do
  LeanLsp.Runtime.Docker.exec(runtime, ["lean", "--version"], [])
after
  LeanLsp.Runtime.Docker.stop(runtime)
end
```

The Docker implementation uses `docker stop` during cleanup and treats an already-missing container as cleaned up.

Supervised callers can use `LeanLsp.Runtime.Docker.child_spec/1` and let the supervisor lifecycle stop the runtime process.

The local runtime does not start a Docker container. Callers should still stop the local runtime process when they are finished:

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    runtime: LeanLsp.Runtime.Local,
    workdir: File.cwd!()
  )

try do
  LeanLsp.Runtime.Local.exec(runtime, ["lean", "--version"], [])
after
  LeanLsp.Runtime.Local.stop(runtime)
end
```

## Expected Docker-related errors

When Docker is unavailable, the Docker runtime cannot start and returns `{:error, reason}`.

The exact reason is implementation-specific during the v0.2.1 preview, but common causes include:

- Docker is not installed.
- Docker is not running or is unreachable from the BEAM process.
- The current user does not have permission to run Docker.
- The selected image cannot be pulled or started.
- Invalid runtime options such as malformed mounts, environment variables, or timeouts.

Code should match on `{:ok, runtime}` / `{:error, reason}` rather than relying on undocumented nested Docker error details.

## Expected local-runtime errors

When a local command cannot be executed, the local runtime returns `{:error, reason}`.

Common causes include:

- The executable is not installed.
- The executable is not reachable through the process `PATH`.
- The configured working directory does not exist.
- The command exits with a non-zero status.
- The command exceeds the configured timeout.
- Invalid runtime options such as malformed environment variables or timeouts.

Code should match on the documented runtime callback result shape rather than relying on undocumented nested local-runtime error details.