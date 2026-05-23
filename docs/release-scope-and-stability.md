# Release scope and stability

This document defines the public scope for the v0.2.1 Hex release.

## Release decision

v0.2.1 is a **runtime-preview** release.

Publishing v0.2.1 to Hex is acceptable only if the package description, README, changelog, and HexDocs consistently describe the release as experimental and preview-only.

The release should not be described as a production-ready Lean LSP client.

## Public contract in v0.2.1

The following APIs are stable enough for users to try during the 0.2.x line:

| API | Status | Contract |
| --- | --- | --- |
| `LeanLsp.runtime_config/1` | Public preview | Normalizes runtime options and returns either `{:ok, %LeanLsp.Runtime.Config{}}` or `{:error, reason}`. |
| `LeanLsp.start_runtime/1` | Public preview | Starts the configured runtime and returns `{:ok, runtime}` or `{:error, reason}`. |
| `LeanLsp.Runtime` | Public preview | Defines the runtime behaviour callbacks `start_link/1`, `stop/1`, and `exec/3`. |
| `LeanLsp.Runtime.Config` | Public preview | Documents runtime defaults and converts normalized configuration to runtime implementation options. |
| `LeanLsp.Runtime.Docker` | Public preview | Provides a Docker-backed implementation of the runtime behaviour, including container startup, command execution, and cleanup. |
| `LeanLsp.Runtime.Local` | Public preview | Provides a host-backed implementation of the runtime behaviour for environments that already have local Lean, Lake, Elan, or other required executables available. |

The documented callback return shapes in `LeanLsp.Runtime` are part of the preview contract.

Implementation-specific runtime state, Docker command arguments, generated container names, internal helper modules, host process implementation details, and undocumented nested error detail shapes are not part of the public compatibility contract.

## Runtime selection

Docker remains the default runtime in v0.2.1.

The default runtime path is intended for reproducible and CI-oriented workflows where Docker is available and the selected image can be pulled or is already present locally.

The local runtime path is intended for development environments where Lean, Lake, or related tools are already installed on the host machine. It avoids starting Docker, but it depends on the host environment.

## Explicitly out of scope for v0.2.1

The following are intentionally unavailable or unstable in v0.2.1:

- A production-ready Lean LSP client.
- Stable public APIs for Lean LSP requests or editor-style queries.
- `LeanLsp.Session`, `LeanLsp.Transport`, or `LeanLsp.Protocol` as usable public modules.
- JSON-RPC request lifecycle management.
- `textDocument/didOpen`, `textDocument/didChange`, `textDocument/didClose`, diagnostics, hover, completion, go-to-definition, or similar LSP features.
- Lean project fixtures and integration-test coverage that proves complete LSP workflows.
- Stability guarantees for Docker internals or generated runtime implementation details.
- Stability guarantees for local host command launch internals.
- A guarantee that a local Lean/Lake installation exists on users' machines.

## 0.x compatibility policy

LeanLsp is experimental while its version is below 1.0.0.

Patch releases in the same 0.x minor line should avoid breaking the documented public preview contract unless the change is necessary to fix safety, correctness, or package-publication issues.

Minor 0.x releases may introduce breaking changes to preview APIs. Breaking changes should be documented in the changelog and should keep the README and HexDocs aligned with the new release scope.

Undocumented modules, private helpers, internal process state, Docker command construction, host command construction, and implementation-specific error details may change without deprecation during 0.x.

## User-facing readiness statement

A user installing `lean_lsp` v0.2.1 from Hex should understand the following before adopting it:

> LeanLsp v0.2.1 is an experimental runtime-preview package. It can be used to explore runtime configuration, Docker-backed command execution, and host-backed local command execution, but it is not yet a production-ready Lean LSP client.