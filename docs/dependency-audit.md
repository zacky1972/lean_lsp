# Dependency audit

LeanLsp v0.2.1 should expose only dependencies that are needed by package users at runtime.

Development tooling must stay in `:dev` and `:test` so it is not part of runtime dependency resolution for downstream applications.

## Production dependency decision

| Dependency | Scope | Runtime reason | Hex package | License decision |
| --- | --- | --- | --- | --- |
| `docker_availability` | Production/runtime | `LeanLsp.Runtime.Docker` calls `DockerAvailability.check/0` before starting the default Docker-backed runtime. | Yes | Apache-2.0; compatible with this package license. |

Expected Hex dry-run production dependency list for v0.2.1:

```text
docker_availability ~> 1.0
```

`docker_availability` is intentionally kept as a production dependency because Docker availability probing is part of the public Docker runtime startup path.

`LeanLsp.Runtime.Local` should not introduce an additional production dependency. It should rely on Elixir/Erlang standard library facilities for host command execution unless a future release explicitly documents another dependency.

## Development and test dependency decisions

| Dependency | Scope | Reason | Hex package | License decision |
| --- | --- | --- | --- | --- |
| `nstandard` | `only: [:dev, :test]`, `runtime: false` | Repository standards, linting, CI, and Hex publish-readiness setup. It is not called by `lib/` at runtime. | Yes | Apache-2.0; compatible with this package license. |
| `ex_doc` | `only: [:dev, :test]`, `runtime: false` | Documentation generation. | Yes | Apache-2.0; compatible with this package license. |
| `dialyxir` | `only: [:dev, :test]`, `runtime: false` | Dialyzer integration for local checks. | Yes | Apache-2.0; compatible with this package license. |
| `credo` | `only: [:dev, :test]`, `runtime: false` | Static analysis during local and CI checks. | Yes | MIT; permissive and compatible with this package license. |
| `spellweaver` | `only: [:dev, :test]`, `runtime: false` | Spelling checks for documentation and repository text. | Yes | Apache-2.0; compatible with this package license. |

These dependencies should not appear as production dependencies in `mix hex.publish --dry-run --yes` output.

## Maintainer validation commands

Run these before publishing:

```sh
mix deps.unlock --check-unused
mix dependency.audit
mix publish.check
```

`mix dependency.audit` runs the unused-lock check and a non-interactive Hex dry run.

`mix publish.check` owns the broader pre-publish path for package build, documentation generation, downstream smoke testing, and Hex dry-run validation.

## Audit expectations for v0.2.1

Before publishing v0.2.1, confirm:

- production dependencies are limited to dependencies required by runtime users;
- development and test tooling dependencies have `only: [:dev, :test]` and `runtime: false`;
- local runtime support does not accidentally introduce a new production dependency;
- `mix hex.publish --dry-run --yes` does not list development-only tools as package runtime dependencies;
- `mix deps.unlock --check-unused` passes.