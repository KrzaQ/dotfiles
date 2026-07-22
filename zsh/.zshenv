[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# ~/.local/bin belongs here rather than in .zprofile because .zshenv is the only file a
# non-login, non-interactive shell reads -- which is what `ssh host make …` runs. uv lives
# there, so without this the Makefile's `uv run` fails remotely while working fine in any
# shell you actually sit in.
#
# Appended, not prepended: the distro's binaries keep winning, as they did when .zprofile
# owned this line. `typeset -U` keeps the entry single if something adds it again.
typeset -U path PATH
[[ -d "$HOME/.local/bin" ]] && path+=("$HOME/.local/bin")
