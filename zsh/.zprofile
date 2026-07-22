export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8
export EDITOR=vim
# SSH_AUTH_SOCK is set per-host in .zprofile.local
# (e.g. systemd agent socket, WSL interop, or left to SSH forwarding)

export GTEST_COLOR=1

[[ -x ~/.rbenv/bin/rbenv ]] && eval "$(~/.rbenv/bin/rbenv init - --no-rehash zsh)"

# ~/.local/bin is added in .zshenv, so non-login shells get it too.
[[ -d $HOME/.npm-global/bin ]] && export PATH=$PATH:$HOME/.npm-global/bin
[[ -d $HOME/.bun/bin ]] && export PATH=$PATH:$HOME/.bun/bin
[[ -d $HOME/.opencode/bin ]] && export PATH=$PATH:$HOME/.opencode/bin

# Per-host overrides
[[ -f ~/.zprofile.local ]] && source ~/.zprofile.local
