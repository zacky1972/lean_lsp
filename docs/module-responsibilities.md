# Module responsibilities

This note records the module boundaries for LeanLsp.

In v0.2.0, the runtime layer is the supported preview surface and the full LSP client layer is roadmap work. For the v0.2.0 public contract and compatibility policy, see [Release scope and stability](release-scope-and-stability.md).

## Architecture flow

```text
Application code
  -> LeanLsp
  -> LeanLsp.Session
  -> LeanLsp.Protocol
  -> LeanLsp.Transport
  -> LeanLsp.Runtime
      -> LeanLsp.Runtime.Docker
      -> LeanLsp.Runtime.Local
  -> Lean language server or Lean-capable command environment
```

`LeanLsp.Runtime` owns process and runtime execution.

`LeanLsp.Runtime.Docker` owns Docker-backed execution.

`LeanLsp.Runtime.Local` owns host-backed execution.

`LeanLsp.Session`, `LeanLsp.Transport`, and `LeanLsp.Protocol` are the intended LSP client-layer boundaries, but they should not be presented as production-ready public APIs in v0.2.0.

## Responsibility map

| Module | Owns | Does not own | v0.2.0 status |
| --- | --- | --- | --- |
| `LeanLsp` | Public entry point for application code. It validates user options, selects or configures a runtime, and starts runtimes. | Docker internals, host process internals, JSON-RPC framing, transport loops, or low-level protocol parsing. | Public preview. |
| `LeanLsp.Runtime` | The runtime contract for starting, stopping, and executing commands in a Lean-capable runtime. It defines runtime callbacks and normalizes runtime results. | LSP request identifiers, document state, protocol payloads, Docker command details, or local host command internals. | Public preview. |
| `LeanLsp.Runtime.Config` | Runtime option normalization and documented runtime defaults. | Docker command construction, host process launching, LSP protocol handling, or transport framing. | Public preview. |
| `LeanLsp.Runtime.Docker` | The Docker implementation of the runtime contract: image selection, container setup, file system mounts, working directory and environment options, command execution, and cleanup. | Public LSP API functions, JSON-RPC framing, protocol payloads, host process semantics, or session state. | Public preview. |
| `LeanLsp.Runtime.Local` | The host-backed implementation of the runtime contract: working directory handling, host command execution, environment propagation, timeout handling, and cleanup of the runtime process. | Docker image selection, container setup, JSON-RPC framing, protocol payloads, or session state. | Public preview. |
| `LeanLsp.Session` | Future LSP conversation state: initialization state, request identifiers, pending requests, open documents, diagnostics cache, and coordination between protocol and transport. | Starting containers, selecting Docker images, launching host commands directly, building Docker commands, or cleaning up runtime resources. | Roadmap. |
| `LeanLsp.Transport` | Future byte-level LSP transport over a runtime process: `Content-Length` framing, reads and writes, JSON message handoff, and transport error reporting. | Runtime selection, Docker management, local command launching, request lifecycle state, document state, or protocol payload construction. | Roadmap. |
| `LeanLsp.Protocol` | Future LSP and JSON-RPC data shapes: request, response, and notification payload construction and parsing. It should remain free of IO and process concerns. | Reads, writes, timers, process management, container management, local command execution, or public API option validation. | Roadmap. |

## Runtime-internal helper modules

Runtime-internal helper modules may exist to reduce duplication between runtime implementations.

Examples include helpers for:

- child specs
- command validation
- command result formatting
- environment validation and normalization
- option validation
- system command execution

These modules are implementation details unless they are explicitly documented as public preview APIs.

Application code should prefer the public entry points:

- `LeanLsp.runtime_config/1`
- `LeanLsp.start_runtime/1`
- `LeanLsp.Runtime`
- documented runtime implementation modules

## Boundary rules

- Docker-specific code belongs only in `LeanLsp.Runtime.Docker`, or in runtime tests that explicitly exercise that module.
- Host process execution code belongs only in `LeanLsp.Runtime.Local` or runtime-internal helpers shared by runtime implementations.
- The LSP client layer is planned as `LeanLsp`, `LeanLsp.Session`, `LeanLsp.Transport`, and `LeanLsp.Protocol`.
- Future LSP client modules must not contain Docker CLI strings, image names, container identifiers, mount rules, local process launch details, or runtime cleanup logic.
- `LeanLsp.Session` may ask `LeanLsp.Runtime` for a server process and may pass messages through `LeanLsp.Transport`, but it must not know which runtime implementation supplied the process.
- `LeanLsp.Transport` moves framed messages. It should be reusable for any runtime that exposes a process-like read and write channel.
- `LeanLsp.Protocol` builds and parses protocol data. Keep side effects, retries, timers, process supervision, and runtime selection outside it.
- `LeanLsp` is the public entry point. Prefer adding user-facing functions there and keeping internal modules behind that API unless a lower-level function is intentionally documented.

## Where future code belongs

| Change | Add it under |
| --- | --- |
| Runtime selection, runtime option validation, process execution contract, or shared runtime result normalization | `LeanLsp.Runtime` or runtime-internal helper modules |
| Docker startup, Docker image names, Docker command construction, file system mounts, container identifiers, or Docker cleanup | `LeanLsp.Runtime.Docker` |
| Host command execution, local working directory handling, host environment propagation, local command timeouts, or local launch failures | `LeanLsp.Runtime.Local` |
| `Content-Length` framing, read and write loops, message buffering, or transport errors | `LeanLsp.Transport` |
| Request identifier allocation, pending request registry, initialization state, document state, or diagnostics state | `LeanLsp.Session` |
| LSP method payloads, JSON-RPC requests, responses, notifications, or protocol parsing | `LeanLsp.Protocol` |
| User-facing functions such as `start_link/1`, query helpers, option validation, and examples | `LeanLsp` |