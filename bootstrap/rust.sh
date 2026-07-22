#!/usr/bin/env bash
set -euo pipefail

# Installs the Rust toolchain (`cargo`), which `bootstrap/limes.sh` needs to build lim.
#
# Idempotent: with a toolchain already present this is a no-op that just reports versions,
# so `make bootstrap-limes` can depend on it unconditionally. Updating is opt-in via
# `--update` (`make bootstrap-rust ARGS=--update`) — bootstrap should never mutate a
# working toolchain behind your back, especially not as a side effect of installing lim.

UPDATE=0
for arg in "$@"; do
    case "$arg" in
        --update) UPDATE=1 ;;
        *) echo "usage: rust.sh [--update]" >&2; exit 2 ;;
    esac
done

# Checks cargo rather than rustup: a distro-packaged toolchain satisfies everything this
# repo needs, and layering rustup on top of it would be wrong. The ~/.cargo/bin probe
# catches the case where rustup was installed earlier in this same make run, before PATH
# picked it up.
resolve() {
    if command -v "$1" &>/dev/null; then
        command -v "$1"
    elif [[ -x "$HOME/.cargo/bin/$1" ]]; then
        echo "$HOME/.cargo/bin/$1"
    fi
}

CARGO="$(resolve cargo)"
RUSTUP="$(resolve rustup)"

if [[ -n "$CARGO" ]]; then
    echo "cargo is already installed: $("$CARGO" --version)"

    if [[ -z "$RUSTUP" ]]; then
        # No rustup means the toolchain came from a package manager (or a very old
        # rustup-less install); updating it is that package manager's job, not ours.
        echo "No rustup found — this toolchain is externally managed, update it there."
        exit 0
    fi

    if (( UPDATE )); then
        echo "Updating rustup and toolchains..."
        # self-update is disabled on package-manager builds of rustup; that is a warning,
        # not an error, so it does not abort the toolchain update below.
        "$RUSTUP" self update || true
        "$RUSTUP" update
    else
        echo "Re-run with \`make bootstrap-rust ARGS=--update\` to update it."
    fi
    exit 0
fi

# --no-modify-path is load-bearing: rustup otherwise appends its PATH snippet to shell
# startup files, and ~/.zshenv is a symlink into this repo, so it would write into a
# tracked file. zsh/.zshenv already sources ~/.cargo/env.
echo "Installing rustup..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

echo "Rust installed. Restart your shell or run:"
echo '  . "$HOME/.cargo/env"'
