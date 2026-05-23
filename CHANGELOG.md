# Changelog

# Changelog

## v0.2.1

### Release scope

LeanLsp v0.2.1 is a patch release in the v0.2 runtime-preview line.
It remains experimental and does not provide a production-ready Lean LSP client.

### Fixed

- Fixed Docker runtime startup for images whose default ENTRYPOINT can reinterpret
  the managed keepalive container command.
- Preserved explicit caller-provided Docker ENTRYPOINT overrides.

### Added

- Added Docker integration coverage for the Issue #72 runtime-boundary regression.
- Added direct Docker ENTRYPOINT diagnostic coverage for the selected Lean image.

### Compatibility

The public runtime-preview API remains compatible with v0.2.0. Docker command
construction remains preview-internal while LeanLsp is below 1.0.0.

## v0.2.0

### Release scope

LeanLsp v0.2.0 is a runtime-preview release for the Lean-capable runtime layer. It remains experimental and does not provide a production-ready Lean LSP client.

### Added

- Added `LeanLsp.Runtime.Local` as a host-backed runtime implementation for environments that already have Lean/Lake installed.
- Added local runtime support through the existing `LeanLsp.Runtime` behaviour.
- Added acceptance coverage for host working directory execution, environment propagation, stdout/stderr capture, non-zero exits, timeout handling, and launch failures.
- Added runtime-internal helper modules to reduce duplication between runtime implementations, if included in the release.

### Fixed

- Fixed Dialyzer type boundaries around Docker command result handling.
- Fixed internal environment-to-CLI argument conversion so map input preserves the intended argument order.

### Compatibility

Docker remains the default runtime. The package is still below 1.0.0, so minor 0.x releases may evolve preview APIs.

## v0.1.0

### Release scope

LeanLsp v0.1.0 is the first Hex release candidate for the repository foundation
and Docker-backed runtime layer. It is a preview release intended for users who
want to evaluate runtime configuration and Docker execution boundaries before the
higher-level Lean LSP client API is implemented.

### Included

- Public runtime entry points:
  - `LeanLsp.runtime_config/1`
  - `LeanLsp.start_runtime/1`
- `LeanLsp.Runtime` behaviour for runtime implementations, including
  `start_link/1`, `stop/1`, and `exec/3`.
- `LeanLsp.Runtime.Config` for normalizing runtime options and applying defaults.
- `LeanLsp.Runtime.Docker` as the Docker-backed runtime implementation.
- Docker container startup, command execution through `docker exec`, and cleanup
  through `docker stop`.
- Runtime defaults:
  - Docker image: `leanprovercommunity/lean4:latest`
  - Container workspace root: `/workspace`

### Requirements and limitations

- Docker must be installed and reachable from the environment running the package.
- v0.1.0 does not provide a production-ready Lean LSP client.
- High-level Lean query APIs are not available yet.
- `Session`, `Transport`, and `Protocol` functionality for JSON-RPC/LSP request
  lifecycle management is not implemented yet.
- Editor-style features such as diagnostics, hover, completion, go-to-definition,
  and document open/change/close lifecycle handling are out of scope for this
  release.
- Docker command internals, generated container names, runtime process state, and
  implementation-specific error details should be treated as preview internals.

### Compatibility

The 0.1.x line should preserve the documented runtime preview contract where
practical. Later 0.x minor releases may change preview APIs as the runtime and
Lean LSP client design evolves.
