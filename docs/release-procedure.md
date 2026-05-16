# v0.2.0 release procedure

This checklist is for maintainers publishing `lean_lsp` v0.2.0 to Hex.

v0.2.0 is a runtime-preview release for the Lean-capable runtime layer. It keeps the package experimental, adds the host-backed local runtime path, and preserves Docker as the default runtime. It is not a production-ready Lean LSP client.

The goal is to publish v0.2.0 from a clean, current `main` branch with matching metadata, documentation, package contents, release notes, and downstream smoke-test coverage.

## 1. Prepare the release branch

Fetch the latest repository state and confirm the release commit is based on the current `main` branch:

```sh
git fetch origin main --tags
git switch main
git pull --ff-only origin main
git status --short
```

Confirm that the release branch contains the intended v0.2.0 runtime changes:

- `LeanLsp.Runtime.Local` is present and documented if the local runtime is included in this release.
- Docker remains the default runtime.
- Runtime configuration still accepts Docker-backed execution.
- Local runtime configuration does not require Docker-specific options.
- Dialyzer fixes for Docker command result typing and environment CLI argument conversion are included.
- No private downstream project names or private module names are mentioned in public documentation.

Confirm that these files describe version `0.2.0` consistently:

- `mix.exs`
- `README.md`
- `CHANGELOG.md`
- `docs/hex-package-metadata.md`
- `docs/release-procedure.md`
- `docs/dependency-audit.md`
- `docs/release-scope-and-stability.md`
- `docs/module-responsibilities.md`
- `docs/runtime-dependency-and-docker-policy.md`
- `docs/hex-package-contents.md`
- `docs/downstream-smoke-test.md`
- release-related tests under `test/`

Confirm that `README.md`, `CHANGELOG.md`, and HexDocs still present v0.2.0 as a runtime-preview release, not as a production-ready Lean LSP client.

Search for stale release text:

```sh
rg 'v0\.1\.0|0\.1\.0|0\.1\.1|first Hex|first public|first publish' \
  README.md CHANGELOG.md docs scripts test mix.exs
```

Expected remaining references are limited to historical changelog entries or explicit references to previous releases.

Confirm there are no uncommitted changes before the final validation pass:

```sh
git status --short
```

## 2. Authenticate with Hex

Publishing requires a Hex account that has permission to publish `lean_lsp`.

```sh
mix hex.user auth
mix hex.user whoami
```

If needed, confirm package ownership:

```sh
mix hex.owner list lean_lsp
```

`lean_lsp` already exists on Hex, so this release is a new version of an existing package rather than the first package publication.

Do not use `--yes` for the final publish command. The final publish should remain an explicit maintainer action.

`HEX_API_KEY` is not required for this local manual release procedure. If a future automation flow uses `HEX_API_KEY`, keep it scoped to publish permissions and do not commit it to the repository.

## 3. Run pre-publish validation

Install dependencies:

```sh
mix deps.get
```

Run the repository quality gate:

```sh
mix check
```

Run the release-specific checks:

```sh
mix test
mix docs --warnings-as-errors
mix package.contents
LEAN_LSP_DOWNSTREAM_DOCKER=skip mix downstream.smoke
mix dependency.audit
LEAN_LSP_DOWNSTREAM_DOCKER=skip mix publish.check
```

`mix publish.check` is intentionally non-publishing. It builds and unpacks the package, generates docs with warnings as errors, runs the downstream smoke test, and runs the Hex dry run with `--dry-run --yes` to avoid interactive prompts.

The `--yes` flag is acceptable only in non-publishing dry-run checks. Do not use it for the final `mix hex.publish`.

When Docker is available and the release is intended to validate Docker runtime startup, also run:

```sh
LEAN_LSP_DOWNSTREAM_DOCKER=required mix downstream.smoke
```

## 4. Inspect package contents

After `mix package.contents` or `mix publish.check`, inspect the unpacked package:

```sh
find _build/hex_package_contents -maxdepth 4 -type f | sort
find _build/hex_publish_check -maxdepth 4 -type f | sort
```

The package should include:

- `.formatter.exs`
- `mix.exs`
- `README.md`
- `LICENSE.md`
- `CHANGELOG.md`
- `lib/`
- `docs/`

The runtime source included under `lib/` should include the public runtime modules intended for v0.2.0, including:

- `LeanLsp`
- `LeanLsp.Runtime`
- `LeanLsp.Runtime.Config`
- `LeanLsp.Runtime.Docker`
- `LeanLsp.Runtime.Local`

If runtime-internal helper modules are included, they should be packaged as part of `lib/`, but they should not be presented as public preview APIs unless intentionally documented.

The package should not include:

- `_build/`
- `deps/`
- `doc/`
- `tmp/`
- `cover/`
- `.elixir_ls/`
- `priv/plts/`
- compiled `.beam` files
- tests
- CI-only scripts

## 5. Publish to Hex

Immediately before publishing, confirm that the package metadata is correct:

```sh
mix hex.publish --dry-run
```

Review the dry-run output for:

- package name: `lean_lsp`
- version: `0.2.0`
- description
- license: `Apache-2.0`
- links
- production dependencies
- included files

Publish manually:

```sh
mix hex.publish
```

Review the package summary printed by Hex. Confirm the version, description, license, links, production dependencies, and package contents before answering the final prompt.

## 6. Tag and create the GitHub release

After the Hex package is published successfully, tag the exact release commit:

```sh
git tag -a v0.2.0 -m "v0.2.0"
git push origin v0.2.0
```

Create the GitHub release from the tag:

```sh
gh release create v0.2.0 \
  --verify-tag \
  --title "v0.2.0" \
  --notes "LeanLsp v0.2.0 runtime-preview release."
```

The GitHub release notes should point users to:

- `CHANGELOG.md`
- the Hex package page
- HexDocs
- the source tag `v0.2.0`

If the tag already exists, do not move it after publishing without also deciding how to handle the published Hex version.

## 7. Verify Hex and HexDocs

After publishing and tagging, verify the public package page and generated documentation:

- `https://hex.pm/packages/lean_lsp`
- `https://hexdocs.pm/lean_lsp`
- `https://hexdocs.pm/lean_lsp/0.2.0`

Check that Hex shows:

- version `0.2.0`
- package description
- Apache-2.0 license
- GitHub link
- HexDocs link
- intended production dependencies only

Check that HexDocs renders:

- README
- CHANGELOG
- release scope and stability notes
- dependency audit
- package contents note
- runtime dependency and Docker/local runtime policy
- downstream smoke-test note
- module responsibilities
- release procedure

Check that HexDocs source links point to the `v0.2.0` tag.

Run the downstream smoke test against the published Hex package:

```sh
LEAN_LSP_DOWNSTREAM_DEP=hex \
LEAN_LSP_HEX_REQUIREMENT="~> 0.2.0" \
LEAN_LSP_DOWNSTREAM_DOCKER=skip \
mix downstream.smoke
```

Use Docker-required mode when Docker runtime verification is intended and Docker is available:

```sh
LEAN_LSP_DOWNSTREAM_DEP=hex \
LEAN_LSP_HEX_REQUIREMENT="~> 0.2.0" \
LEAN_LSP_DOWNSTREAM_DOCKER=required \
mix downstream.smoke
```

## 8. Update, revert, or correct a bad v0.2.0 publish

If the published release has a problem, act quickly and document what changed.

Documentation-only problems can usually be corrected with:

```sh
mix hex.publish docs
```

A newly published version of an existing package can be updated or reverted during Hex's update window.

For v0.2.0, use:

```sh
mix hex.publish --revert 0.2.0
```

Then fix the issue, rerun the full pre-publish validation, and publish again.

If the update window has closed, do not try to replace the published package. Prepare a follow-up version such as `0.2.1`, update the changelog, update release metadata, and publish the correction as a new release.

After any update, revert, or documentation republish, verify:

- Hex package page
- HexDocs
- downstream dependency smoke test
- Git tag
- GitHub release