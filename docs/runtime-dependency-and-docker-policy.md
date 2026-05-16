# Runtime dependency and Docker image policy

LeanLsp v0.1.0 exposes a Docker-backed Lean runtime preview. Users can install
and inspect configuration without Docker, but starting the default runtime
requires Docker.

## External runtime requirement

Docker is required for the default runtime path:

- `LeanLsp.runtime_config/1` validates and normalizes options without starting
  Docker.
- `LeanLsp.start_runtime/1` starts `LeanLsp.Runtime.Docker` by default and needs
  a reachable Docker executable.
- The calling environment must have permission to run Docker containers.
- The selected image must be available locally or pullable by Docker.

A local Lean installation on the host is not required for this Docker-first
runtime path.

## Default image policy

The v0.1.0 preview default image is:

```text
leanprovercommunity/lean4:latest
```

The package keeps `latest` as the default for the initial preview so users get a
small, convenient Lean runtime without choosing an image up front. This is a
convenience default, not a reproducibility guarantee.

For reproducible workflows, pass a pinned tag or immutable digest explicitly with the public
`:docker_image` option:

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    docker_image: "leanprovercommunity/lean4:<pinned-tag-or-digest>"
  )
```

When calling `LeanLsp.Runtime.Docker.start_link/1` directly, use the runtime
`:image` option name:

```elixir
{:ok, runtime} =
  LeanLsp.Runtime.Docker.start_link(
    image: "leanprovercommunity/lean4:<pinned-tag-or-digest>"
  )
```

## Workspace and mount behaviour

`:container_workspace_root` configures the working directory inside the
container. It does not automatically mount a host directory.

Host filesystem access is opt-in through runtime-specific mount options:

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    container_workspace_root: "/workspace",
    mounts: [{File.cwd!(), "/workspace", "ro"}]
  )
```

Docker bind mounts can expose host files to the container. Use read-only mounts
such as `"ro"` when the runtime only needs to read project files.

## Container lifecycle and cleanup

`LeanLsp.start_runtime/1` starts a long-lived Docker container. The returned
runtime handle is opaque and should be passed to `LeanLsp.Runtime.Docker.exec/3`
and `LeanLsp.Runtime.Docker.stop/1`.

Callers that start the runtime directly are responsible for stopping it:

```elixir
{:ok, runtime} = LeanLsp.start_runtime()

try do
  LeanLsp.Runtime.Docker.exec(runtime, ["lean", "--version"], [])
after
  LeanLsp.Runtime.Docker.stop(runtime)
end
```

The Docker implementation uses `docker stop` during cleanup and treats an
already-missing container as cleaned up. Supervised callers can use
`LeanLsp.Runtime.Docker.child_spec/1` and let the supervisor lifecycle stop the
runtime process.

## Expected Docker-related errors

When Docker is unavailable, the runtime cannot start and returns `{:error,
reason}`. The exact reason is implementation-specific during the v0.1.0 preview,
but common causes include:

- Docker is not installed.
- Docker is not running or is unreachable from the BEAM process.
- The current user does not have permission to run Docker.
- The selected image cannot be pulled or started.
- Invalid runtime options such as malformed mounts, environment variables, or
  timeouts.

Code should match on `{:ok, runtime}` / `{:error, reason}` rather than relying on
undocumented nested Docker error details.
