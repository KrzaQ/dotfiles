#!/usr/bin/env bash
set -euo pipefail

# Installs `pi` (the pi coding agent) with its pi-censor extension. goniec also runs pi for its
# local-model bots.
# vendor/pi pins the whole dependency tree with a lockfile, and `npm ci` installs exactly that
# tree into its own directory. --ignore-scripts keeps package install scripts from running.

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$DOTFILES_DIR/vendor/pi"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/pi-coding-agent"
BIN="$HOME/.local/bin/pi"
NODE_MIN=22.19.0

if ! command -v npm &>/dev/null; then
    echo "npm not found — install Node.js $NODE_MIN or newer first."
    exit 1
fi

node_version="$(node --version)"
node_version="${node_version#v}"
if [[ "$(printf '%s\n%s\n' "$NODE_MIN" "$node_version" | sort -V | head -n1)" != "$NODE_MIN" ]]; then
    echo "pi needs Node.js $NODE_MIN or newer; this machine has $node_version."
    exit 1
fi

# pi asks before no tool call; pi-censor makes interactive sessions ask. It is deployed first,
# so a failure here stops before pi is installed. PI_CENSOR_REPO wins, so a machine where
# pi-censor is being developed deploys that working tree instead of the pinned submodule.
CENSOR="${PI_CENSOR_REPO:-$DOTFILES_DIR/vendor/pi-censor}"
if [[ -z "${PI_CENSOR_REPO:-}" ]]; then
    (cd "$DOTFILES_DIR" && git submodule update --init vendor/pi-censor)
fi
if [[ ! -f "$CENSOR/Makefile" ]]; then
    echo "No pi-censor checkout at $CENSOR; pi is not installed without it."
    echo "Run \`make submodules\`, or set PI_CENSOR_REPO=/path/to/pi-censor."
    exit 1
fi
(cd "$CENSOR" && make deploy)

# The stamp is a copy of the lockfile, written only after a successful install.
stamp="$DEST/.installed-lock"
if cmp -s "$SRC/package-lock.json" "$stamp" && [[ -x "$DEST/node_modules/.bin/pi" ]]; then
    echo "pi is already installed and current ($DEST)."
else
    mkdir -p "$DEST"
    rm -f "$stamp"
    cp "$SRC/package.json" "$SRC/package-lock.json" "$DEST/"
    (cd "$DEST" && npm ci --ignore-scripts --no-audit --no-fund)
    cp "$SRC/package-lock.json" "$stamp"
    echo "pi installed in $DEST."
fi

target="$DEST/node_modules/.bin/pi"
if [[ -e "$BIN" || -L "$BIN" ]] && [[ "$(readlink "$BIN")" != "$target" ]]; then
    echo "$BIN exists and is not this install's link; leaving it alone."
    exit 1
fi
mkdir -p "$(dirname "$BIN")"
ln -sfn "$target" "$BIN"
echo "pi: $BIN"
