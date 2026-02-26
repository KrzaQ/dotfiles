export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8
export EDITOR=vim
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

export GTEST_COLOR=1

[[ -x ~/.rbenv/bin/rbenv ]] && eval "$(~/.rbenv/bin/rbenv init - --no-rehash zsh)"

export PATH=$PATH:$HOME/.local/bin
[[ -d $HOME/.npm-global/bin ]] && export PATH=$PATH:$HOME/.npm-global/bin
[[ -d $HOME/.bun/bin ]] && export PATH=$PATH:$HOME/.bun/bin
[[ -d $HOME/.opencode/bin ]] && export PATH=$PATH:$HOME/.opencode/bin

# Per-host overrides
[[ -f ~/.zprofile.local ]] && source ~/.zprofile.local
