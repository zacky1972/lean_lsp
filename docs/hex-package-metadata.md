# Hex package metadata

This note records the v0.2.1 package metadata expected for the `lean_lsp` Hex release.

`lean_lsp` already exists on Hex, so v0.2.1 is a new version of an existing public package.

| Field | Value |
| --- | --- |
| Package name | `lean_lsp` |
| Display name | `LeanLsp` |
| Version | `0.2.1` |
| Source URL | `https://github.com/zacky1972/lean_lsp` |
| Home page URL | `https://github.com/zacky1972/lean_lsp` |
| HexDocs URL | `https://hexdocs.pm/lean_lsp` |
| License | `Apache-2.0` |

The GitHub repository is both the source location and the project home page for v0.2.1.

HexDocs source navigation is generated from the project `source_url` and `docs[:source_ref]` metadata in `mix.exs`. For v0.2.1, `docs[:source_ref]` should point to the release tag:

```elixir
source_ref: "v0.2.1"
```

For the full v0.2.1 release checklist, see [Release procedure](release-procedure.md).

## Release description

The package description should describe the runtime-preview scope without claiming production-ready Lean LSP client support.

Suggested description:

```text
Experimental Lean LSP runtime foundation for Elixir; full LSP client support is roadmap work.
```

If the release includes `LeanLsp.Runtime.Local`, the description should not remain Docker-only.

## Public links

The Hex package should expose these links:

| Link | Target |
| --- | --- |
| GitHub | `https://github.com/zacky1972/lean_lsp` |
| HexDocs | `https://hexdocs.pm/lean_lsp` |
| Changelog | `https://github.com/zacky1972/lean_lsp/blob/main/CHANGELOG.md` |

The changelog link may continue to point at `main`, but generated HexDocs source links should point at the immutable `v0.2.1` tag.

## Pre-publish checks

Before publishing v0.2.1, run the pre-publish validation alias from a clean working tree:

```sh
mix publish.check
```

The alias is safe to run locally. It does not publish a package, does not perform the final interactive publish, and does not require a `HEX_API_KEY`.

It validates the release in three Hex-specific ways:

- `mix hex.build --unpack --output _build/hex_publish_check` builds the package and unpacks its contents for local inspection.
- `mix docs --warnings-as-errors` verifies that HexDocs generation still succeeds without warnings.
- `mix hex.publish --dry-run --yes` validates package metadata and local publish checks without uploading anything and without interactive prompts.

The `--yes` flag is used only together with `--dry-run` so that the pre-publish check remains non-interactive. The final publish command remains a manual maintainer action and should not use `--yes`.

Inspect `_build/hex_publish_check` before the final publish and confirm that the package contains the expected source files, README, CHANGELOG, license, and release-scope documentation. Local Dialyzer PLTs and other generated development artifacts should not be present.

## Ownership check

Immediately before publishing, confirm that the current Hex user is authorized to publish `lean_lsp`:

```sh
mix hex.user whoami
mix hex.owner list lean_lsp
```

If the current user is not an owner of `lean_lsp`, do not publish until ownership has been corrected.