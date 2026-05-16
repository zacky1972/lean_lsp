# LeanLsp

LeanLsp is an experimental Lean LSP foundation and Docker runtime preview for
Elixir.

Version 0.1.0 is an initial Hex release for the runtime layer. It lets users
install the package, normalize runtime configuration, start the Docker-backed
runtime, and execute commands through the runtime behaviour. It is not a
production-ready Lean LSP client yet.

## Installation

For the v0.1.0 Hex release, add `lean_lsp` to your dependencies:

```elixir
def deps do
  [
    {:lean_lsp, "~> 0.1.0"}
  ]
end
```

## Package links

The package and documentation use these canonical public locations:

| Resource | Link |
| --- | --- |
| Hex package | [hex.pm/packages/lean_lsp](https://hex.pm/packages/lean_lsp) |
| HexDocs | [hexdocs.pm/lean_lsp](https://hexdocs.pm/lean_lsp) |
| Source repository | [github.com/zacky1972/lean_lsp](https://github.com/zacky1972/lean_lsp) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |

The Hex package and HexDocs links become live after v0.1.0 is published.

## Requirements

For package users:

- Elixir `~> 1.19`, as declared in `mix.exs`.
- An Erlang/OTP version supported by the Elixir version used in your project.
- Docker installed and reachable from the environment that starts the runtime.
- Permission to run Docker containers and either pull or already have access to
  the default image, `leanprovercommunity/lean4:latest`.

A local Lean installation is not required for the Docker-first runtime path.
`LeanLsp.runtime_config/1` can be used without Docker; `LeanLsp.start_runtime/1`
uses Docker by default.

## Quick start

Normalize the default runtime configuration:

```elixir
{:ok, config} = LeanLsp.runtime_config()

%LeanLsp.Runtime.Config{
  runtime: LeanLsp.Runtime.Docker,
  docker_image: "leanprovercommunity/lean4:latest",
  container_workspace_root: "/workspace"
} = config
```

Start the Docker runtime and run a Lean command:

```elixir
{:ok, runtime} = LeanLsp.start_runtime()

try do
  {:ok, result} = LeanLsp.Runtime.Docker.exec(runtime, ["lean", "--version"], [])
  IO.puts(result.stdout)
after
  LeanLsp.Runtime.Docker.stop(runtime)
end
```

The second example requires Docker. If Docker is not installed, unavailable, or
not permitted for the current user, runtime startup returns an error.

## Release status

v0.1.0 is a **foundation/runtime-preview** release. It is suitable for trying the
package metadata, runtime configuration, and Docker-backed runtime boundary. It
is intentionally not a complete language-server client.

## Included in v0.1.0

| Area | Status |
| --- | --- |
| Package metadata and HexDocs extras | Public release surface |
| `LeanLsp.runtime_config/1` | Public preview API |
| `LeanLsp.start_runtime/1` | Public preview API |
| `LeanLsp.Runtime` | Public preview behaviour |
| `LeanLsp.Runtime.Config` | Public preview configuration struct and normalizer |
| `LeanLsp.Runtime.Docker` | Public preview Docker-backed runtime implementation |

The documented runtime defaults are:

| Option | Default |
| --- | --- |
| `:runtime` | `LeanLsp.Runtime.Docker` |
| `:docker_image` | `leanprovercommunity/lean4:latest` |
| `:container_workspace_root` | `/workspace` |

## Not included yet

The following features are roadmap work and should not be treated as available
in v0.1.0:

- A production-ready Lean LSP client.
- Stable application-level APIs for Lean LSP requests.
- `LeanLsp.Session`, `LeanLsp.Transport`, and `LeanLsp.Protocol` as usable public
  modules.
- Lean document open/change/close lifecycle management.
- Diagnostics, hover, completion, go-to-definition, or other editor-style query
  helpers.
- Lean fixture projects and integration-test coverage for complete LSP workflows.
- Compatibility guarantees for Docker command internals, generated container
  names, runtime process state, or implementation-specific error detail shapes.

## 0.x compatibility policy

LeanLsp is experimental while its version is below 1.0.0.

Patch releases in the same 0.x minor line should avoid breaking the documented
public preview contract unless a correction is required for safety, correctness,
or package-publication issues.

Minor 0.x releases may change, rename, or remove preview APIs when the runtime
and LSP client design evolves. Undocumented modules, private helpers, internal
process state, Docker command construction, and implementation-specific error
details may change without deprecation during 0.x.

## Roadmap

| Milestone | Focus | Outcome |
| --- | --- | --- |
| v0.1.0: Foundation/runtime preview | Package metadata, quality gate, architecture notes, runtime configuration, and Docker-backed runtime boundary. | Users can install the package from Hex, read the public stability policy, and experiment with the runtime layer without expecting a complete LSP client. |
| Next: Minimal Lean LSP client over Docker | Implement the first usable session, transport, and protocol flow over the Docker runtime. | Application code can start a session and send minimal LSP requests to Lean through the Docker-backed runtime. |
| Later: Integration fixtures and production hardening | Add Lean fixture projects, integration tests, richer LSP methods, and reliability work. | Users can evaluate production readiness based on tested Lean LSP workflows. |

## Architecture

LeanLsp separates runtime execution from the LSP client layer. Docker-specific
code belongs in `LeanLsp.Runtime.Docker`; future Session, Transport, and Protocol
code should use the runtime abstraction instead of calling Docker directly.

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

## Module responsibilities

| Module | v0.1.0 status | Responsibility |
| --- | --- | --- |
| `LeanLsp` | Public preview API | Public entry point for application code. In v0.1.0 it validates runtime options and starts runtimes. |
| `LeanLsp.Runtime` | Public preview API | Runtime behaviour for starting, stopping, and executing commands in a Lean-capable runtime. |
| `LeanLsp.Runtime.Config` | Public preview API | Runtime option normalization and documented runtime defaults. |
| `LeanLsp.Runtime.Docker` | Public preview API | Docker-backed implementation of the runtime contract, including image selection, container setup, command execution, and cleanup. |
| `LeanLsp.Session` | Roadmap | Future LSP conversation state, including initialization state, request identifiers, pending requests, document state, and diagnostics state. |
| `LeanLsp.Transport` | Roadmap | Future byte-level LSP transport, including `Content-Length` framing, reads, writes, buffering, and transport errors. |
| `LeanLsp.Protocol` | Roadmap | Future LSP and JSON-RPC data construction and parsing. It should stay free of IO, process, and Docker concerns. |

For detailed boundary rules, see
[Module responsibilities](docs/module-responsibilities.md).

## Runtime configuration

Runtime configuration is explicit and normalized through
`LeanLsp.Runtime.Config`.

```elixir
{:ok, runtime} =
  LeanLsp.start_runtime(
    docker_image: "leanprovercommunity/lean4:latest",
    container_workspace_root: "/workspace"
  )

LeanLsp.Runtime.Docker.stop(runtime)
```

## Additional documentation

- [Release scope and stability](docs/release-scope-and-stability.md)
- [Hex package metadata](docs/hex-package-metadata.md)
- [Module responsibilities](docs/module-responsibilities.md)
- [Changelog](CHANGELOG.md)

## Development setup

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

## License

Copyright (c) 2026 University of Kitakyushu

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
You may obtain a copy of the License at <http://www.apache.org/licenses/LICENSE-2.0>.

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and limitations under the License.
