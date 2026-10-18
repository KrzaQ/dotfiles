#!/usr/bin/env bash
set -euo pipefail

# Installs `rosa` (sub rosa — a secret broker with a human approval gate on its own tty).
# rosa has its own repo; dotfiles carries it as the `vendor/sub-rosa` submodule, the same way
# it carries limes, so a fresh machine needs no manual clone. This installs the binary and
# seeds a config; creating the store (`rosa init`) and running it (`rosa serve`) stay manual
# because both need a passphrase and a tty.

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# ROSA_REPO wins, so a machine where rosa is being *developed* builds that working tree
# instead of the pinned submodule.
REPO="${ROSA_REPO:-$DOTFILES_DIR/vendor/sub-rosa}"
stamp_file="${XDG_DATA_HOME:-$HOME/.local/share}/rosa/.installed-commit"

# What a build here would produce. `rosa --version` reports only the crate version, so without
# a stamp any installed `rosa` looks current and a submodule bump can never reach the machine
# that needs it. The superproject's index entry is the fallback because it is readable even
# when the submodule has never been checked out — exactly when we must not claim to be current.
rosa_commit() {
    if [[ -e "$REPO/.git" ]]; then
        local commit
        commit="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || return 1
        if [[ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]]; then
            commit="$commit-dirty"
        fi
        printf '%s\n' "$commit"
    else
        git -C "$DOTFILES_DIR" rev-parse ":vendor/sub-rosa" 2>/dev/null || return 1
    fi
}

# Seed ~/.config/rosa/config.toml from the example, never clobbering an existing one: it holds
# per-machine choices (gpg_recipient, the store path) that a re-run must not overwrite.
seed_config() {
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/rosa"
    local cfg="$dir/config.toml"
    if [[ ! -e "$cfg" ]]; then
        mkdir -p "$dir"
        cp "$REPO/config.example.toml" "$cfg"
        echo "Wrote $cfg — set 'gpg_recipient' before \`rosa init\`."
    fi
}

# A `git pull` of dotfiles moves the pin but not the submodule checkout, and the check below
# reads the checkout. Without this sync, an old build would pass as current.
if [[ -z "${ROSA_REPO:-}" ]]; then
    (cd "$DOTFILES_DIR" && git submodule update --init vendor/sub-rosa)
fi

want="$(rosa_commit || true)"
have="$(cat "$stamp_file" 2>/dev/null || true)"

# A dirty tree never matches: its commit says nothing about the uncommitted edit someone is
# presumably trying to test.
if command -v rosa &>/dev/null && [[ -n "$want" && "$want" == "$have" && "$want" != *-dirty ]]
then
    echo "rosa is already installed and current: $(rosa --version) ($want)"
    seed_config
    exit 0
fi

if [[ ! -f "$REPO/Cargo.toml" ]]; then
    echo "No sub-rosa checkout at $REPO (no Cargo.toml)."
    echo "Run \`make submodules\`, or set ROSA_REPO=/path/to/sub-rosa."
    exit 1
fi

# Same fallback the Makefile uses for `lim`: when bootstrap-rust just installed rustup in this
# very run, cargo exists but is not on PATH yet.
CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
if [[ ! -x "$CARGO" ]]; then
    echo "cargo not found — run \`make bootstrap-rust\` first, then re-run."
    exit 1
fi

if command -v rosa &>/dev/null; then
    echo "Rebuilding rosa from $REPO (installed: ${have:-unknown}, wanted: ${want:-unknown})..."
else
    echo "Installing rosa from $REPO..."
fi
"$CARGO" install --path "$REPO"

# Only after a build that succeeded: a stamp written eagerly would mark a failed install as
# current and skip the retry.
mkdir -p "$(dirname "$stamp_file")"
printf '%s\n' "$want" > "$stamp_file"
echo "rosa installed ($want)."

seed_config

# rosa encrypts its store with gpg; without it (and a key) `rosa init`/`add`/`serve` all fail.
# A warning, not an install: this script stays non-root.
if ! command -v gpg &>/dev/null; then
    echo "WARNING: gpg not found — rosa encrypts its store with gpg, so install it before \`rosa init\`."
fi

cat <<'EOF'

rosa is installed. What remains is manual — it needs your passphrase and a tty:
  rosa init                  # create the empty encrypted store (~/.config/rosa/secrets.json.gpg)
  rosa add <NAME>            # add a secret (value typed hidden)
  rosa serve                 # run the approval TUI in a dedicated tmux/screen window

`rosa serve` is deliberately not a service: its approval gate must be on a terminal the
requesting process can't reach. Once it's running, limes sandboxes on this machine get the
rosa socket and client automatically.
EOF
