# LeanLsp

LeanLsp is an OTP-native Elixir client for running and querying Lean's
language server, with Docker-backed runtime support.

## Status and next target

LeanLsp is currently in repository foundation work. The next implementation
target is **Milestone 1: Docker Runtime Foundation**.

The project is Docker-first: the Docker runtime is implemented before LSP
client support. Milestone 1 establishes the runtime that can start, stop, and
communicate with Lean's language server through Docker. Milestone 2 then builds
the minimal Lean LSP client on top of that runtime.

The Lean fixture project for integration testing is deferred, so the current
repository does not assume that `test/fixtures/simple_project/` exists.

## Roadmap

| Milestone | Focus | Outcome |
| --- | --- | --- |
| Milestone 0: Repository Foundation Completion | Finish repository-level foundations: package metadata, CI quality gate, module responsibility notes, and this README. The Lean fixture project is deferred. | Contributors can understand the roadmap, quality gate, and initial module boundaries before runtime work starts. |
| Milestone 1: Docker Runtime Foundation | Implement `LeanLsp.Runtime` and `LeanLsp.Runtime.Docker`. | The project can manage a Docker-backed Lean language server process without exposing Docker details to the LSP client layer. |
| Milestone 2: Minimal Lean LSP Client over Docker | Implement the first usable Session, Transport, and Protocol flow over the Docker runtime. | Application code can start a session and send minimal LSP requests to Lean through the Docker-backed runtime. |

## Architecture

LeanLsp separates runtime execution from the LSP client layer. Docker-specific
code belongs in `LeanLsp.Runtime.Docker`; Session, Transport, and Protocol code
use the runtime abstraction instead of calling Docker directly.

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

For the detailed boundary rules, see
[Module responsibilities](docs/module-responsibilities.md).

## Module responsibilities

| Module | Responsibility |
| --- | --- |
| `LeanLsp` | Public API for application code. It validates user options, starts sessions, and delegates internal work. |
| `LeanLsp.Runtime` | Runtime contract for starting, stopping, and communicating with a Lean language server process. |
| `LeanLsp.Runtime.Docker` | Docker-backed implementation of the runtime contract, including image selection, container setup, mounts, process startup, and cleanup. |
| `LeanLsp.Session` | LSP conversation state, including initialization state, request identifiers, pending requests, document state, and diagnostics state. |
| `LeanLsp.Transport` | Byte-level LSP transport, including `Content-Length` framing, reads, writes, buffering, and transport errors. |
| `LeanLsp.Protocol` | LSP and JSON-RPC data construction and parsing. It stays free of IO, process, and Docker concerns. |

## Runtime configuration

LeanLsp runtime configuration is explicit and normalized through
`LeanLsp.Runtime.Config`.

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
  
## Development setup

### Prerequisites

- Elixir and Erlang/OTP versions compatible with `mix.exs`.
- Docker for Milestone 1 and later runtime work.
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

Run `mix check` before opening a pull request. It is the repository quality gate
used by CI.

### Run local pre-commit checks

```sh
mix precommit
```

`mix precommit` is intended for local use when you want formatting fixes and the
full local validation path.

## Installation

If the package is available in Hex, it can be installed by adding `lean_lsp` to
your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lean_lsp, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with
[ExDoc](https://github.com/elixir-lang/ex_doc) and published on
[HexDocs](https://hexdocs.pm). Once published, the docs can be found at
[https://hexdocs.pm/lean_lsp](https://hexdocs.pm/lean_lsp).
