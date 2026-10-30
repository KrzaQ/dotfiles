#!/usr/bin/env bash
set -euo pipefail

# Installs `goniec` (Zulip inboxes for the agent sessions on this host) from the
# `vendor/goniec` submodule. The daemon's user service is the opt-in `goniec-daemon` module.

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# GONIEC_REPO wins, so a machine where goniec is being developed builds that working tree.
REPO="${GONIEC_REPO:-$DOTFILES_DIR/vendor/goniec}"
stamp_file="${XDG_DATA_HOME:-$HOME/.local/share}/goniec/.installed-commit"

# Same scheme as bootstrap/rosa.sh: `goniec --version` reports only the crate version, so the
# stamp is what lets a submodule bump reach the machine.
goniec_commit() {
    if [[ -e "$REPO/.git" ]]; then
        local commit
        commit="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || return 1
        if [[ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]]; then
            commit="$commit-dirty"
        fi
        printf '%s\n' "$commit"
    else
        git -C "$DOTFILES_DIR" rev-parse ":vendor/goniec" 2>/dev/null || return 1
    fi
}

if [[ -z "${GONIEC_REPO:-}" ]]; then
    (cd "$DOTFILES_DIR" && git submodule update --init vendor/goniec)
fi

want="$(goniec_commit || true)"
have="$(cat "$stamp_file" 2>/dev/null || true)"

if command -v goniec &>/dev/null && [[ -n "$want" && "$want" == "$have" && "$want" != *-dirty ]]
then
    echo "goniec is already installed and current: $(goniec --version) ($want)"
    exit 0
fi

if [[ ! -f "$REPO/Cargo.toml" ]]; then
    echo "No goniec checkout at $REPO (no Cargo.toml)."
    echo "Run \`make submodules\`, or set GONIEC_REPO=/path/to/goniec."
    exit 1
fi

CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
if [[ ! -x "$CARGO" ]]; then
    echo "cargo not found — run \`make bootstrap-rust\` first, then re-run."
    exit 1
fi

if command -v goniec &>/dev/null; then
    echo "Rebuilding goniec from $REPO (installed: ${have:-unknown}, wanted: ${want:-unknown})..."
else
    echo "Installing goniec from $REPO..."
fi
"$CARGO" install --locked --path "$REPO"

mkdir -p "$(dirname "$stamp_file")"
printf '%s\n' "$want" > "$stamp_file"
echo "goniec installed ($want)."

# A running daemon keeps the old binary until it restarts. It finishes its running headless
# turns first, which can take minutes, so do not wait for it.
if command -v systemctl &>/dev/null && systemctl --user -q is-active goniec.service 2>/dev/null; then
    systemctl --user daemon-reload
    systemctl --user restart --no-block goniec.service
    echo "goniec.service restarts once its running headless turns finish."
fi
