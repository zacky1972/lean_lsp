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

## Pre-publish checks

Before publishing v0.1.0, run these checks from a clean working tree:

```sh
mix format
mix docs
mix hex.publish --dry-run
mix check
```

Also confirm immediately before publishing that no public Hex package has claimed `lean_lsp`. Package-name availability can change after this document is written, so the final check should happen at publish time.
