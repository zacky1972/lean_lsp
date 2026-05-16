# v0.1.0 release procedure

This checklist is for maintainers publishing the first public `lean_lsp` Hex
release. The goal is to publish v0.1.0 from a clean, current `main` branch with
matching metadata, documentation, package contents, and downstream smoke-test
coverage.

## 1. Prepare the release branch

1. Fetch the latest repository state and confirm the release commit is based on
   the current `main` branch:

   ```sh
   git fetch origin main --tags
   git switch main
   git pull --ff-only origin main
   git status --short
   ```

2. Confirm that `mix.exs`, `README.md`, `CHANGELOG.md`, and the release
   readiness docs all describe version `0.1.0`.
3. Confirm that `README.md` still presents v0.1.0 as a
   foundation/runtime-preview release, not as a production-ready Lean LSP client.
4. Confirm there are no uncommitted changes before the final validation pass.

## 2. Authenticate with Hex

Publishing requires a Hex account that has permission to publish `lean_lsp`.

```sh
mix hex.user auth
mix hex.user whoami
```

If Hex asks whether the package should be owned by an individual account or an
organization, choose the owner intentionally before confirming the first publish.
Do not use `--yes` for the final publish command; the final publish should remain
an explicit maintainer action.

`HEX_API_KEY` is not required for the local manual release procedure. If a future
automation flow uses `HEX_API_KEY`, keep it scoped to publish permissions and do
not commit it to the repository.

## 3. Run pre-publish validation

Run the full project quality gate:

```sh
mix deps.get
mix check
```

Run the release-specific checks:

```sh
mix test
mix docs --warnings-as-errors
mix package.contents
LEAN_LSP_DOWNSTREAM_DOCKER=skip mix downstream.smoke
mix dependency.audit
mix publish.check
```

`mix publish.check` is intentionally non-publishing. It builds and unpacks the
package, generates docs with warnings as errors, runs the downstream smoke test,
and runs the Hex dry run with `--dry-run --yes` to avoid interactive prompts.

## 4. Inspect package contents

After `mix package.contents` or `mix publish.check`, inspect the unpacked package:

```sh
find _build/hex_publish_check -maxdepth 3 -type f | sort
```

The package should include the source files, README, CHANGELOG, license, and docs
extras. It should not include `_build`, `deps`, `doc`, `tmp`, `cover`, `.elixir_ls`,
`priv/plts`, compiled `.beam` files, tests, or CI-only scripts.

## 5. Publish to Hex

Immediately before publishing, confirm that `lean_lsp` is still available or is
owned by the expected maintainer account.

Publish manually:

```sh
mix hex.publish
```

Review the package summary printed by Hex. Confirm the version, description,
license, links, production dependencies, and package contents before answering the
final prompt.

## 6. Verify Hex and HexDocs

After publishing, verify the public package page and generated documentation:

- `https://hex.pm/packages/lean_lsp`
- `https://hexdocs.pm/lean_lsp`
- `https://hexdocs.pm/lean_lsp/0.1.0`

Check that Hex shows version `0.1.0`, the package description, the Apache-2.0
license, the GitHub and HexDocs links, and only the intended production
dependencies.

Check that HexDocs renders the README, CHANGELOG, release scope and stability
notes, dependency audit, package contents note, runtime dependency policy,
downstream smoke-test note, module responsibilities, and this release procedure.

Run the downstream smoke test against the published Hex package:

```sh
LEAN_LSP_DOWNSTREAM_DEP=hex LEAN_LSP_DOWNSTREAM_DOCKER=skip mix downstream.smoke
```

Use `LEAN_LSP_DOWNSTREAM_DOCKER=required` when Docker runtime verification is
intended and Docker is available.

## 7. Tag and create the GitHub release

After the Hex package and HexDocs have been verified, tag the exact release
commit:

```sh
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

Create the GitHub release from the tag:

```sh
gh release create v0.1.0 \
  --verify-tag \
  --title "v0.1.0" \
  --notes "Initial Hex foundation/runtime-preview release for LeanLsp."
```

The GitHub release notes should point users to `CHANGELOG.md`, Hex, and HexDocs.
If the tag already exists, do not move it after publishing without also deciding
how to handle the published Hex version.

## 8. Revert, update, or correct a bad first publish

If the first publish has a problem, act quickly and document what changed.

- Documentation-only problems can usually be corrected with:

  ```sh
  mix hex.publish docs
  ```

- A newly published package can be updated or reverted during Hex's first-release
  update window. For v0.1.0, use:

  ```sh
  mix hex.publish --revert 0.1.0
  ```

  Then fix the issue, rerun the full pre-publish validation, and publish again.

- If the update window has closed, do not try to replace the published package.
  Prepare a follow-up version such as `0.1.1`, update the changelog, and publish
  the correction as a new release.

After any revert or update, verify Hex, HexDocs, downstream dependency mode, the
Git tag, and the GitHub release again.
