# Changelog

## v0.1.0

### Release scope

- Defines v0.1.0 as a foundation/runtime-preview release.
- Documents that the package is experimental and not production-ready as a Lean LSP client.
- Narrows the public contract to runtime configuration, the runtime behaviour, and Docker-backed runtime startup, command execution, and cleanup.

### Supported

- `LeanLsp.runtime_config/1` for runtime option normalization.
- `LeanLsp.start_runtime/1` for starting the configured runtime.
- `LeanLsp.Runtime` as the runtime behaviour contract.
- `LeanLsp.Runtime.Docker` as the Docker-backed runtime implementation.
- ExDoc/HexDocs extras covering release scope, public stability, and module responsibilities.

### Not yet available

- Stable application-level Lean LSP request or query APIs.
- Production-ready Session, Transport, or Protocol modules.
- Diagnostics, hover, completion, go-to-definition, document lifecycle, or editor-style helper APIs.
- Lean fixture integration project and production-hardening guarantees.

### Compatibility policy

- 0.1.x patch releases should preserve the documented preview contract where practical.
- Later 0.x minor releases may change preview APIs as the runtime and LSP client design evolves.
