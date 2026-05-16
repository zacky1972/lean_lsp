# Downstream dependency smoke test

The downstream smoke test verifies that `lean_lsp` can be consumed from a fresh
Mix project before the initial Hex release. A package can pass its own unit tests
but still fail when compiled as a dependency, so this check exercises the
external dependency boundary.

## Before the first Hex publish

Run the smoke test with the local repository as a path dependency:

```sh
mix downstream.smoke
```

The script creates a temporary Mix project with `mix new`, adds `lean_lsp` as a
local `path:` dependency, runs `mix deps.get`, compiles the downstream project
with warnings as errors, and calls the public `LeanLsp.runtime_config/1` API from
the downstream project.

## Docker runtime check

Docker is optional for the default smoke run. The script supports three modes:

```sh
LEAN_LSP_DOWNSTREAM_DOCKER=auto mix downstream.smoke
LEAN_LSP_DOWNSTREAM_DOCKER=skip mix downstream.smoke
LEAN_LSP_DOWNSTREAM_DOCKER=required mix downstream.smoke
```

`auto` is the default. In this mode, the script starts and stops the default
Docker runtime only when Docker is available. If Docker is unavailable, the
Docker runtime check is reported as skipped. Use `required` when validating an
environment that must be able to start the Docker-backed runtime.

## After the first Hex publish

After `lean_lsp` is published on Hex, repeat the same smoke test with the real
Hex dependency:

```sh
LEAN_LSP_DOWNSTREAM_DEP=hex mix downstream.smoke
```

The default Hex requirement is `~> 0.1.0`. Override it when validating a specific
published version:

```sh
LEAN_LSP_DOWNSTREAM_DEP=hex \
LEAN_LSP_HEX_REQUIREMENT="~> 0.1.1" \
mix downstream.smoke
```

## Keeping the generated project

Set `LEAN_LSP_DOWNSTREAM_KEEP=1` to keep the temporary downstream project for
inspection after the smoke test finishes:

```sh
LEAN_LSP_DOWNSTREAM_KEEP=1 mix downstream.smoke
```

## Release checklist integration

`mix publish.check` runs `mix downstream.smoke` before the final Hex dry-run
publish step. This smoke test is intentionally not part of `mix check` because it
creates another Mix project, fetches dependencies, and may start Docker depending
on environment settings.
