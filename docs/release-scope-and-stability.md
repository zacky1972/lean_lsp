# Release scope and stability

This document defines the public scope for the v0.1.0 Hex release.

## Release decision

v0.1.0 is a **foundation/runtime-preview** release.

Publishing v0.1.0 to Hex is acceptable only if the package description, README, changelog, and HexDocs consistently describe the release as experimental and preview-only. The release should not be described as a production-ready Lean LSP client.

## Public contract in v0.1.0

The following APIs are stable enough for users to try during the 0.1.x line:

| API | Status | Contract |
| --- | --- | --- |
| `LeanLsp.runtime_config/1` | Public preview | Normalizes runtime options and returns either `{:ok, %LeanLsp.Runtime.Config{}}` or `{:error, reason}`. |
| `LeanLsp.start_runtime/1` | Public preview | Starts the configured runtime and returns `{:ok, runtime}` or `{:error, reason}`. |
| `LeanLsp.Runtime` | Public preview | Defines the runtime behaviour callbacks `start_link/1`, `stop/1`, and `exec/3`. |
| `LeanLsp.Runtime.Config` | Public preview | Documents runtime defaults and converts normalized configuration to runtime implementation options. |
| `LeanLsp.Runtime.Docker` | Public preview | Provides a Docker-backed implementation of the runtime behaviour, including container startup, command execution, and cleanup. |

The documented callback return shapes in `LeanLsp.Runtime` are part of the preview contract. Implementation-specific runtime state, Docker command arguments, generated container names, and undocumented error detail shapes are not part of the public compatibility contract.

## Explicitly out of scope for v0.1.0

The following are intentionally unavailable or unstable in v0.1.0:

- A production-ready Lean LSP client.
- Stable public APIs for Lean LSP requests or editor-style queries.
- `LeanLsp.Session`, `LeanLsp.Transport`, or `LeanLsp.Protocol` as usable public modules.
- JSON-RPC request lifecycle management.
- `textDocument/didOpen`, `textDocument/didChange`, `textDocument/didClose`, diagnostics, hover, completion, go-to-definition, or similar LSP features.
- Lean project fixtures and integration-test coverage that proves complete LSP workflows.
- Stability guarantees for Docker internals or generated runtime implementation details.

## 0.x compatibility policy

LeanLsp is experimental while its version is below 1.0.0.

Patch releases in the same 0.x minor line should avoid breaking the documented public preview contract unless the change is necessary to fix safety, correctness, or package-publication issues.

Minor 0.x releases may introduce breaking changes to preview APIs. Breaking changes should be documented in the changelog and should keep the README and HexDocs aligned with the new release scope.

Undocumented modules, private helpers, internal process state, Docker command construction, and implementation-specific error details may change without deprecation during 0.x.

## User-facing readiness statement

A user installing `lean_lsp` v0.1.0 from Hex should understand the following before adopting it:

> LeanLsp v0.1.0 is an experimental foundation/runtime-preview package. It can be used to explore the runtime configuration and Docker-backed runtime boundary, but it is not yet a production-ready Lean LSP client.
