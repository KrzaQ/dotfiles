#!/usr/bin/env bash
set -euo pipefail

# Installs `lim` (the limes host-mirroring sandbox). limes has its own repo; dotfiles
# carries it as the `vendor/limes` submodule, the same way it carries the zsh plugins,
# so a fresh machine needs no manual clone. `make bootstrap-limes` chains the rest
# (prereqs, config drop-in, `lim bootstrap`).

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# LIMES_REPO wins, so a machine where limes is being *developed* builds that working tree
# instead of the pinned submodule.
REPO="${LIMES_REPO:-$DOTFILES_DIR/vendor/limes}"
stamp_file="${XDG_DATA_HOME:-$HOME/.local/share}/limes/.installed-commit"

# What a build here would produce. `lim --version` cannot answer this -- it has read 0.1.0
# since the first commit -- so without a stamp any installed `lim` looks current and a
# submodule bump can never reach the machine that needs it.
#
# The superproject's index entry is the fallback because it is readable even when the
# submodule has never been checked out, which is exactly when we must not claim to be
# up to date.
limes_commit() {
    if [[ -e "$REPO/.git" ]]; then
        local commit
        commit="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || return 1
        if [[ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]]; then
            commit="$commit-dirty"
        fi
        printf '%s\n' "$commit"
    else
        git -C "$DOTFILES_DIR" rev-parse ":vendor/limes" 2>/dev/null || return 1
    fi
}

want="$(limes_commit || true)"
have="$(cat "$stamp_file" 2>/dev/null || true)"

# A dirty tree never matches: its commit says nothing about the uncommitted edit someone
# is presumably trying to test.
if command -v lim &>/dev/null && [[ -n "$want" && "$want" == "$have" && "$want" != *-dirty ]]
then
    echo "lim is already installed and current: $(lim --version) ($want)"
    exit 0
fi

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
    want="$(limes_commit || true)"
fi

# Same fallback the Makefile uses for `lim`: when bootstrap-rust just installed rustup in
# this very run, cargo exists but is not on PATH yet.
CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
if [[ ! -x "$CARGO" ]]; then
    echo "cargo not found — run \`make bootstrap-rust\` first, then re-run."
    exit 1
fi

if command -v lim &>/dev/null; then
    echo "Rebuilding lim from $REPO (installed: ${have:-unknown}, wanted: ${want:-unknown})..."
else
    echo "Installing lim from $REPO..."
fi
"$CARGO" install --path "$REPO"

# Only after a build that succeeded: a stamp written eagerly would mark a failed install
# as current and skip the retry.
mkdir -p "$(dirname "$stamp_file")"
printf '%s\n' "$want" > "$stamp_file"
echo "lim installed ($want)."
