# Hex package contents

The v0.2.1 Hex package uses an explicit `package[:files]` list so release contents do not depend on Hex defaults.

## Included files

The release package should include:

- `.formatter.exs`
- `mix.exs`
- `README.md`
- `LICENSE.md`
- `CHANGELOG.md`
- `lib/`
- `docs/`

The `docs/` directory is included because `docs()` references documentation extras such as:

- `docs/hex-package-metadata.md`
- `docs/release-procedure.md`
- `docs/dependency-audit.md`
- `docs/release-scope-and-stability.md`
- `docs/module-responsibilities.md`
- `docs/runtime-dependency-and-docker-policy.md`
- `docs/hex-package-contents.md`
- `docs/downstream-smoke-test.md`

Keeping the whole `docs/` directory in the package prevents future extras from being added to HexDocs while being left out of the release package.

## Runtime source files

The `lib/` directory should contain the runtime implementation intended for v0.2.1.

The public preview runtime modules should include:

- `lib/lean_lsp.ex`
- `lib/lean_lsp/runtime.ex`
- `lib/lean_lsp/runtime/config.ex`
- `lib/lean_lsp/runtime/docker.ex`
- `lib/lean_lsp/runtime/local.ex`

If runtime-internal helper modules are present, they should also be included through the `lib/` directory. Examples may include modules for command result normalization, environment handling, child specs, option validation, or system command execution.

Internal helper modules are package contents, but they are not part of the public preview API unless explicitly documented as public.

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
- `.github/`
- `scripts/`
- compiled `.beam` files

These files are useful during development, CI, or release validation, but they are not required by users of the package.

## Local inspection

Before publishing, inspect the actual package contents:

```sh
mix package.contents
```

This command builds and unpacks the Hex package under `_build/hex_package_contents` and checks that required release files are present while generated artifacts are absent.

For a second independent inspection, run:

```sh
mix hex.build --unpack --output _build/hex_publish_check
find _build/hex_publish_check -maxdepth 4 -type f | sort
```

Any unexpected generated artifact should be removed from the package before publishing.