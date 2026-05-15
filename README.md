# LeanLsp

LeanLsp is an experimental Lean LSP foundation and Docker runtime preview for Elixir.

Version 0.1.0 is intentionally a foundation/runtime-preview release. It is suitable for trying the package metadata, runtime configuration, and Docker-backed runtime boundary, but it is not a production-ready Lean LSP client yet.

## Release status

v0.1.0 should be published, if at all, as a **foundation/runtime-preview** release rather than as a complete language-server client.

The release is intended to make the runtime boundary installable from Hex while keeping the user-facing contract narrow and explicit. The package does not yet provide application-level Lean query helpers, document lifecycle management, diagnostics collection, hover/completion APIs, or other stable LSP request flows.

## Supported in v0.1.0

The following public surface is stable enough for users to try during the 0.1.x line:

- Package metadata, ExDoc/HexDocs pages, repository quality gate, and architecture notes.
- Runtime configuration normalization through `LeanLsp.runtime_config/1`.
- Runtime startup through `LeanLsp.start_runtime/1`.
- The `LeanLsp.Runtime` behaviour contract for runtime implementations.
- The Docker-backed runtime implementation in `LeanLsp.Runtime.Docker`, including container startup, command execution through `exec/3`, and cleanup through `stop/1`.
- The documented runtime defaults:
  - `:runtime` - `LeanLsp.Runtime.Docker`
  - `:docker_image` - `leanprovercommunity/lean4:latest`
  - `:container_workspace_root` - `/workspace`

## Not supported yet

The following features are roadmap work and should not be treated as available in v0.1.0:

- A production-ready Lean LSP client.
- Stable application-level APIs for Lean LSP requests.
- `LeanLsp.Session`, `LeanLsp.Transport`, and `LeanLsp.Protocol` implementations as public user APIs.
- Lean document open/change/close lifecycle management.
- Diagnostics, hover, completion, go-to-definition, or other editor-style query helpers.
- A Lean fixture project for integration testing.
- Compatibility guarantees for Docker command internals, runtime process state, or implementation-specific error tuple shapes beyond the documented behaviour return contracts.

## 0.x compatibility policy

LeanLsp follows an experimental 0.x policy:

- Patch releases in the same 0.x minor line should avoid breaking the documented public contract unless a correction is required for safety or correctness.
- Minor 0.x releases may change, rename, or remove preview APIs when the runtime and LSP client design evolves.
- APIs, modules, options, and error shapes not documented as part of the public contract may change without deprecation during 0.x.
- Production users should pin compatible versions conservatively and review changelogs before upgrading.

## Roadmap

| Milestone | Focus | Outcome |
| --- | --- | --- |
| v0.1.0: Foundation/runtime preview | Package metadata, quality gate, architecture notes, runtime configuration, and Docker-backed runtime boundary. | Users can install the package from Hex, read the public stability policy, and experiment with the runtime layer without expecting a complete LSP client. |
| Next: Minimal Lean LSP client over Docker | Implement the first usable session, transport, and protocol flow over the Docker runtime. | Application code can start a session and send minimal LSP requests to Lean through the Docker-backed runtime. |
| Later: Integration fixtures and production hardening | Add Lean fixture projects, integration tests, richer LSP methods, and reliability work. | Users can evaluate production readiness based on tested Lean LSP workflows. |

## Architecture

LeanLsp separates runtime execution from the LSP client layer. Docker-specific code belongs in `LeanLsp.Runtime.Docker`; future Session, Transport, and Protocol code should use the runtime abstraction instead of calling Docker directly.

```text
Application code
      |
      v
+----------------+
| LeanLsp        | public API and option validation
+----------------+
      |
      v
+-----------------+       builds and parses       +------------------+
| LeanLsp.Session | <---------------------------> | LeanLsp.Protocol |
| LSP state       |                               | LSP/JSON-RPC     |
+-----------------+                               +------------------+
      |
      | framed messages
      v
+-------------------+
| LeanLsp.Transport | Content-Length framing and IO
+-------------------+
      |
      | process-like IO
      v
+-----------------+
| LeanLsp.Runtime | runtime contract
+-----------------+
      |
      v
+------------------------+
| LeanLsp.Runtime.Docker | Docker implementation
+------------------------+
      |
      v
Lean language server
```

For the detailed boundary rules, see [Module responsibilities](docs/module-responsibilities.md). For the release contract, see [Release scope and stability](docs/release-scope-and-stability.md).

## Module responsibilities

| Module | v0.1.0 status | Responsibility |
| --- | --- | --- |
| `LeanLsp` | Public preview API | Public entry point for application code. In v0.1.0 it validates runtime options and starts runtimes. |
| `LeanLsp.Runtime` | Public preview API | Runtime behaviour for starting, stopping, and executing commands in a Lean-capable runtime. |
| `LeanLsp.Runtime.Docker` | Public preview API | Docker-backed implementation of the runtime contract, including image selection, container setup, command execution, and cleanup. |
| `LeanLsp.Session` | Roadmap | Future LSP conversation state, including initialization state, request identifiers, pending requests, document state, and diagnostics state. |
| `LeanLsp.Transport` | Roadmap | Future byte-level LSP transport, including `Content-Length` framing, reads, writes, buffering, and transport errors. |
| `LeanLsp.Protocol` | Roadmap | Future LSP and JSON-RPC data construction and parsing. It should stay free of IO, process, and Docker concerns. |

## Runtime configuration

LeanLsp runtime configuration is explicit and normalized through `LeanLsp.Runtime.Config`.

Defaults:

| Option | Default |
| --- | --- |
| `:runtime` | `LeanLsp.Runtime.Docker` |
| `:docker_image` | `leanprovercommunity/lean4:latest` |
| `:container_workspace_root` | `/workspace` |

Example:

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    docker_image: "leanprovercommunity/lean4:latest",
    container_workspace_root: "/workspace"
  )
```

## Development setup

### Prerequisites

- Elixir and Erlang/OTP versions compatible with `mix.exs`.
- Docker for the runtime preview path.
- A local Lean installation is not required for the Docker-first runtime path.

### Install dependencies

```sh
mix local.hex --force
mix local.rebar --force
mix deps.get
```

### Run the quality gate

```sh
mix check
```

Run `mix check` before opening a pull request. It is the repository quality gate used by CI.

### Run local pre-commit checks

```sh
mix precommit
```

`mix precommit` is intended for local use when you want formatting fixes and the full local validation path.

## Installation

If the package is available in Hex, it can be installed by adding `lean_lsp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lean_lsp, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm). Once published, the docs can be found at [https://hexdocs.pm/lean_lsp](https://hexdocs.pm/lean_lsp).

## License

Copyright (c) 2026 University of Kitakyushu

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
You may obtain a copy of the License at <http://www.apache.org/licenses/LICENSE-2.0>.

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and limitations under the License.
