export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8
export EDITOR=vim
# SSH_AUTH_SOCK is set per-host in .zprofile.local
# (e.g. systemd agent socket, WSL interop, or left to SSH forwarding)

export GTEST_COLOR=1

[[ -x ~/.rbenv/bin/rbenv ]] && eval "$(~/.rbenv/bin/rbenv init - --no-rehash zsh)"

# Also added in .zshenv, for the non-login shells that never read this file -- but it has
# to be repeated here, not just there. A login shell reads .zshenv, then /etc/zsh/zprofile,
# then this file, and on Debian-family hosts the middle one does
# `emulate sh -c 'source /etc/profile'` -- which *assigns* PATH instead of appending to it,
# discarding whatever .zshenv put there. So the entry survives exactly in the shells you
# never sit in, which is the confusing half of the bug this pairing fixes.
#
# Harmless where /etc/profile leaves PATH alone (arch, fedora): `typeset -U path` from
# .zshenv keeps the leftmost occurrence, so the re-add is a no-op that does not reorder.
[[ -d "$HOME/.local/bin" ]] && path+=("$HOME/.local/bin")

[[ -d $HOME/.npm-global/bin ]] && export PATH=$PATH:$HOME/.npm-global/bin
[[ -d $HOME/.bun/bin ]] && export PATH=$PATH:$HOME/.bun/bin
[[ -d $HOME/.opencode/bin ]] && export PATH=$PATH:$HOME/.opencode/bin

# Per-host overrides
[[ -f ~/.zprofile.local ]] && source ~/.zprofile.local
