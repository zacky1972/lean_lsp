# Hex package metadata

This note records the v0.1.0 package metadata expected for the first public Hex release.

| Field | Value |
| --- | --- |
| Package name | `lean_lsp` |
| Display name | `LeanLsp` |
| Source URL | `https://github.com/zacky1972/lean_lsp` |
| Home page URL | `https://github.com/zacky1972/lean_lsp` |
| HexDocs URL | `https://hexdocs.pm/lean_lsp` |
| License | `Apache-2.0` |

The GitHub repository is both the source location and the project home page for v0.1.0. HexDocs source navigation is generated from the project `source_url` and `docs[:source_ref]` metadata in `mix.exs`.



For the full v0.1.0 release checklist, see [Release procedure](release-procedure.md).

## Pre-publish checks

Before publishing v0.1.0, run the pre-publish validation alias from a clean
working tree:

```sh
mix publish.check
```

The alias is safe to run locally. It does not publish a package, does not pass
`--yes`, and does not require a `HEX_API_KEY`.

It validates the release in three Hex-specific ways:

  * `mix hex.build --unpack --output _build/hex_publish_check` builds the
    package and unpacks its contents for local inspection.
  * `mix docs --warnings-as-errors` verifies that HexDocs generation still
    succeeds without warnings.
  * `mix hex.publish --dry-run --yes` validates package metadata and local
    publish checks without uploading anything and without interactive prompts.

The `--yes` flag is used only together with `--dry-run` so that the pre-publish check remains non-interactive when Hex would otherwise ask for an owner or confirmation. The final publish command remains a manual maintainer action.

Inspect `_build/hex_publish_check` before the final publish and confirm
that the package contains the expected source files, README, CHANGELOG, license,
and release-scope documentation. Local Dialyzer PLTs and other generated
development artifacts should not be present.

Also confirm immediately before publishing that no public Hex package has
claimed `lean_lsp`. Package-name availability can change after this document is
written, so the final check should happen at publish time.
