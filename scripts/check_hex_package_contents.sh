#!/usr/bin/env sh
set -eu

OUT_DIR="${1:-_build/hex_package_contents}"

rm -rf "$OUT_DIR"
mix hex.build --unpack --output "$OUT_DIR"

required_paths="
.formatter.exs
CHANGELOG.md
LICENSE.md
README.md
docs
docs/module-responsibilities.md
  docs/release-procedure.md
lib
lib/lean_lsp.ex
lib/lean_lsp/runtime.ex
lib/lean_lsp/runtime/config.ex
lib/lean_lsp/runtime/docker.ex
lib/lean_lsp/runtime/local.ex
lib/lean_lsp/runtime/child_spec.ex
lib/lean_lsp/runtime/command.ex
lib/lean_lsp/runtime/env.ex
lib/lean_lsp/runtime/options.ex
lib/lean_lsp/runtime/system_command.ex
mix.exs
"

for path in $required_paths; do
  if [ ! -e "$OUT_DIR/$path" ]; then
    printf 'missing required package path: %s\n' "$path" >&2
    exit 1
  fi
done

for path in _build deps doc tmp cover .elixir_ls priv/plts test; do
  if [ -e "$OUT_DIR/$path" ]; then
    printf 'unexpected package path: %s\n' "$path" >&2
    exit 1
  fi
done

if find "$OUT_DIR" -path '*/priv/plts*' -print -quit | grep -q .; then
  printf 'unexpected Dialyzer PLT files in package\n' >&2
  exit 1
fi

if find "$OUT_DIR" -name '*.beam' -print -quit | grep -q .; then
  printf 'unexpected compiled BEAM files in package\n' >&2
  exit 1
fi

printf 'Hex package contents look ready: %s\n' "$OUT_DIR"
