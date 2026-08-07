[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# ~/.local/bin is added here *and* in .zprofile; keep both. This file is the only one a
# non-login, non-interactive shell reads -- which is what `ssh host make …` runs -- and uv
# lives there, so without this line the Makefile's `uv run` fails remotely while working
# fine in any shell you actually sit in. But this line alone does not survive a login
# shell: /etc/zsh/zprofile is read after it and assigns PATH outright, so .zprofile has to
# put the entry back. Deleting either one breaks a different half of the matrix.
#
# Appended, not prepended: the distro's binaries keep winning, as they did when .zprofile
# owned this line. `typeset -U` keeps the entry single if something adds it again.
typeset -U path PATH
[[ -d "$HOME/.local/bin" ]] && path+=("$HOME/.local/bin")
