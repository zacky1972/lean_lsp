# Module responsibilities

This note records the initial module boundaries for LeanLsp before runtime and LSP internals are implemented. Keep these boundaries stable so runtime code, protocol code, and the public API remain easy to place and review.

## Architecture flow

```text
Application code
  -> LeanLsp
  -> LeanLsp.Session
  -> LeanLsp.Protocol
  -> LeanLsp.Transport
  -> LeanLsp.Runtime
  -> LeanLsp.Runtime.Docker
  -> Lean language server
```

`LeanLsp.Runtime` owns process and container execution. `LeanLsp.Session` owns LSP conversation state. The LSP client layer must use the runtime interface instead of calling Docker directly.

## Responsibility map

| Module | Owns | Does not own |
| --- | --- | --- |
| `LeanLsp.Runtime` | The runtime contract for starting, stopping, and communicating with a Lean language server process. It defines runtime options and normalizes runtime results. | LSP request identifiers, document state, protocol payloads, or Docker command details. |
| `LeanLsp.Runtime.Docker` | The Docker implementation of the runtime contract: image selection, container setup, file system mounts, working directory and environment options, server process creation, and cleanup. | Public LSP API functions, JSON-RPC framing, protocol payloads, or session state. |
| `LeanLsp.Session` | LSP conversation state: initialization state, request identifiers, pending requests, open documents, diagnostics cache, and coordination between protocol and transport. | Starting containers, selecting Docker images, building Docker commands, or cleaning up container resources. |
| `LeanLsp.Transport` | Byte-level LSP transport over a runtime process: `Content-Length` framing, reads and writes, JSON message handoff, and transport error reporting. | Request lifecycle state, document state, protocol payload construction, or runtime selection. |
| `LeanLsp.Protocol` | LSP and JSON-RPC data shapes: request, response, and notification payload construction and parsing. It should remain free of IO and process concerns. | Reads, writes, timers, process management, container management, or public API option validation. |
| `LeanLsp` | The stable public API for application code. It validates user options, selects or configures a runtime, starts sessions, and delegates user-facing calls to `LeanLsp.Session`. | Docker internals, JSON-RPC framing, transport loops, or low-level protocol parsing. |

## Boundary rules

- Docker-specific code belongs only in `LeanLsp.Runtime.Docker`, or in runtime tests that explicitly exercise that module.
- The LSP client layer is `LeanLsp`, `LeanLsp.Session`, `LeanLsp.Transport`, and `LeanLsp.Protocol`. These modules must not contain Docker CLI strings, image names, container identifiers, mount rules, or container cleanup logic.
- `LeanLsp.Session` may ask `LeanLsp.Runtime` for a server process and may pass messages through `LeanLsp.Transport`, but it must not know which runtime implementation supplied the process.
- `LeanLsp.Transport` moves framed messages. It should be reusable for any runtime that exposes a process-like read and write channel.
- `LeanLsp.Protocol` builds and parses protocol data. Keep side effects, retries, timers, and process supervision outside it.
- `LeanLsp` is the public entry point. Prefer adding user-facing functions there and keeping internal modules behind that API unless a lower-level function is intentionally documented.

## Where future code belongs

| Change | Add it under |
| --- | --- |
| Runtime selection, process execution, server commands, Docker startup, image names, file system mounts, or cleanup | `LeanLsp.Runtime` or `LeanLsp.Runtime.Docker` |
| `Content-Length` framing, read and write loops, message buffering, or transport errors | `LeanLsp.Transport` |
| Request identifier allocation, pending request registry, initialization state, document state, or diagnostics state | `LeanLsp.Session` |
| LSP method payloads, JSON-RPC requests, responses, notifications, or protocol parsing | `LeanLsp.Protocol` |
| User-facing functions such as `start_link/1`, query helpers, option validation, and examples | `LeanLsp` |
