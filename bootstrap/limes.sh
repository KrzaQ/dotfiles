#!/usr/bin/env bash
set -euo pipefail

# Installs `lim` (the limes host-mirroring sandbox). limes lives in its own repo,
# not in dotfiles — this hook just builds/installs the binary. `make bootstrap-limes`
# chains the rest (prereqs, config drop-in, `lim bootstrap`).

if command -v lim &>/dev/null; then
    echo "lim is already installed: $(lim --version)"
    exit 0
fi

REPO="${LIMES_REPO:-$HOME/code/misc/limes}"

if [[ ! -d "$REPO" ]]; then
    echo "limes repo not found at $REPO"
    echo "Clone it there (or set LIMES_REPO=/path/to/limes), then re-run."
    exit 1
fi

if ! command -v cargo &>/dev/null; then
    echo "cargo not found — install rustup/cargo first, then re-run."
    exit 1
fi

echo "Installing lim from $REPO..."
cargo install --path "$REPO"
echo "lim installed."
