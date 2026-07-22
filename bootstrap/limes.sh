#!/usr/bin/env bash
set -euo pipefail

# Installs `lim` (the limes host-mirroring sandbox). limes has its own repo; dotfiles
# carries it as the `vendor/limes` submodule, the same way it carries the zsh plugins,
# so a fresh machine needs no manual clone. `make bootstrap-limes` chains the rest
# (prereqs, config drop-in, `lim bootstrap`).

if command -v lim &>/dev/null; then
    echo "lim is already installed: $(lim --version)"
    exit 0
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# LIMES_REPO wins, so a machine where limes is being *developed* builds that working tree
# instead of the pinned submodule.
REPO="${LIMES_REPO:-$DOTFILES_DIR/vendor/limes}"

# An uninitialised submodule is an empty directory, not a missing one.
if [[ ! -f "$REPO/Cargo.toml" ]]; then
    if [[ -z "${LIMES_REPO:-}" ]]; then
        echo "Fetching the limes submodule..."
        (cd "$DOTFILES_DIR" && git submodule update --init vendor/limes)
    fi
    if [[ ! -f "$REPO/Cargo.toml" ]]; then
        echo "No limes checkout at $REPO (no Cargo.toml)."
        echo "Run \`make submodules\`, or set LIMES_REPO=/path/to/limes."
        exit 1
    fi
fi

# Same fallback the Makefile uses for `lim`: when bootstrap-rust just installed rustup in
# this very run, cargo exists but is not on PATH yet.
CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
if [[ ! -x "$CARGO" ]]; then
    echo "cargo not found — run \`make bootstrap-rust\` first, then re-run."
    exit 1
fi

echo "Installing lim from $REPO..."
"$CARGO" install --path "$REPO"
echo "lim installed."
