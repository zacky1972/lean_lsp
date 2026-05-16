# Hex package contents

The v0.1.0 Hex package uses an explicit `package[:files]` list so release
contents do not depend on Hex defaults.

## Included files

The release package should include:

- `.formatter.exs`
- `mix.exs`
- `README.md`
- `LICENSE.md`
- `CHANGELOG.md`
- `lib/`
- `docs/`

The `docs/` directory is included because `docs()` references documentation
extras such as `docs/module-responsibilities.md`. Keeping the whole directory in
the package prevents future extras from being added to HexDocs while being left
out of the release package.

## Excluded files

The release package should not include local or generated artifacts such as:

- `_build/`
- `deps/`
- `doc/`
- `tmp/`
- `cover/`
- `.elixir_ls/`
- `priv/plts/`
- `test/`

These files are useful during development, but they are not required by users of
the package.

## Local inspection

Before publishing, inspect the actual package contents:

```sh
mix package.contents
```

This command builds and unpacks the Hex package under `_build/hex_package_contents`
and checks that required release files are present while generated artifacts are
absent.
