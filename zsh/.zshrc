# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=100000
SAVEHIST=100000
setopt HIST_IGNORE_SPACE HIST_IGNORE_DUPS HIST_FIND_NO_DUPS
setopt INC_APPEND_HISTORY EXTENDED_HISTORY HIST_EXPIRE_DUPS_FIRST

bindkey -e

typeset -g -A key

key[Home]="${terminfo[khome]}"
key[End]="${terminfo[kend]}"
key[Insert]="${terminfo[kich1]}"
key[Backspace]="${terminfo[kbs]}"
key[Delete]="${terminfo[kdch1]}"
key[Up]="${terminfo[kcuu1]}"
key[Down]="${terminfo[kcud1]}"
key[Left]="${terminfo[kcub1]}"
key[Right]="${terminfo[kcuf1]}"
key[PageUp]="${terminfo[kpp]}"
key[PageDown]="${terminfo[knp]}"
key[Shift-Tab]="${terminfo[kcbt]}"
key[Control-Left]="${terminfo[kLFT5]}"
key[Control-Right]="${terminfo[kRIT5]}"

# setup key accordingly
[[ -n "${key[Home]}"      ]] && bindkey -- "${key[Home]}"      beginning-of-line
[[ -n "${key[End]}"       ]] && bindkey -- "${key[End]}"       end-of-line
[[ -n "${key[Insert]}"    ]] && bindkey -- "${key[Insert]}"    overwrite-mode
[[ -n "${key[Backspace]}" ]] && bindkey -- "${key[Backspace]}" backward-delete-char
[[ -n "${key[Delete]}"    ]] && bindkey -- "${key[Delete]}"    delete-char
[[ -n "${key[Up]}"        ]] && bindkey -- "${key[Up]}"        up-line-or-history
[[ -n "${key[Down]}"      ]] && bindkey -- "${key[Down]}"      down-line-or-history
[[ -n "${key[Left]}"      ]] && bindkey -- "${key[Left]}"      backward-char
[[ -n "${key[Right]}"     ]] && bindkey -- "${key[Right]}"     forward-char
[[ -n "${key[PageUp]}"    ]] && bindkey -- "${key[PageUp]}"    beginning-of-buffer-or-history
[[ -n "${key[PageDown]}"  ]] && bindkey -- "${key[PageDown]}"  end-of-buffer-or-history
[[ -n "${key[Shift-Tab]}" ]] && bindkey -- "${key[Shift-Tab]}" reverse-menu-complete
[[ -n "${key[Control-Left]}"  ]] && bindkey -- "${key[Control-Left]}"  backward-word
[[ -n "${key[Control-Right]}" ]] && bindkey -- "${key[Control-Right]}" forward-word

# Ensure terminal is in application mode for terminfo key sequences
if (( ${+terminfo[smkx]} && ${+terminfo[rmkx]} )); then
    autoload -Uz add-zle-hook-widget
    function zle_application_mode_start { echoti smkx }
    function zle_application_mode_stop  { echoti rmkx }
    add-zle-hook-widget -Uz zle-line-init zle_application_mode_start
    add-zle-hook-widget -Uz zle-line-finish zle_application_mode_stop
fi

# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename "$HOME/.zshrc"

autoload -U compinit
compinit
autoload -U colors
colors
setopt correct

if [ -x /usr/bin/dircolors ]; then
    eval "`dircolors -b`"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='grep -F --color=auto'
    alias egrep='grep -E --color=auto'
fi

alias df='df -h'
alias mc='mc -u -X'

force_color_prompt=yes
# End of lines added by compinstall

# --- Prompt ---
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' stagedstr '+'
zstyle ':vcs_info:*' unstagedstr '*'
zstyle ':vcs_info:git:*' formats '%b%u%c'
zstyle ':vcs_info:git:*' actionformats '%b|%a%u%c'

typeset -gA _prompt_signals=(
    [129]=HUP  [130]=INT   [131]=QUIT [132]=ILL
    [134]=ABRT [135]=BUS   [136]=FPE  [137]=KILL
    [139]=SEGV [141]=PIPE  [143]=TERM
)

precmd() {
    local last_exit=$?
    vcs_info

    if (( last_exit != 0 )); then
        local sig=""
        if (( last_exit == 127 )); then
            sig=":NOTFOUND"
        elif (( last_exit > 128 )) && [[ -n "${_prompt_signals[$last_exit]}" ]]; then
            sig=":${_prompt_signals[$last_exit]}"
        fi
        _prompt_exitcode="%B%F{red}{${last_exit}${sig}}%f%b"$'\n'
    else
        _prompt_exitcode=$'\n'
    fi

    _prompt_git=""
    if [[ -n "$vcs_info_msg_0_" ]]; then
        if [[ "$vcs_info_msg_0_" == *'*'* || "$vcs_info_msg_0_" == *'+'* ]]; then
            _prompt_git=" %F{yellow}${vcs_info_msg_0_}%f"
        else
            _prompt_git=" %F{green}${vcs_info_msg_0_}%f"
        fi
    fi
}

setopt PROMPT_SUBST

# Context badges — independent, so PRODUCTION and LIM can show at once.
# ($LIMES_VERSION is set by the limes sandbox; $PRODUCTION per-host in .zprofile.local.)
_prompt_badges=''
[[ -n "$PRODUCTION"    ]] && _prompt_badges+='%K{red}%B%F{white} PRODUCTION %f%b%k '
[[ -n "$LIMES_VERSION" ]] && _prompt_badges+='%B%F{208}LIM%f%b '

# Hostname is red under PRODUCTION, orange otherwise (driven by PRODUCTION alone).
if [[ -n "$PRODUCTION" ]]; then
    _prompt_host='%B%F{red}%m%f%b'
else
    _prompt_host='%B%F{208}%m%f%b'
fi

PS1='${_prompt_exitcode}'"${_prompt_badges}"'%(!.%B%F{red}.%F{242})%n%F{242}@%f'"${_prompt_host}"':%F{cyan}%~%f${_prompt_git}%(1j. %F{green}<%j>%f.)
%# '

PS2='%F{red}%_> %f'

# Not in a limes sandbox: no session bus is needed there (ephemeral, single-shell).
if [[ -z "$LIMES_VERSION" ]] && [[ -z "$DBUS_SESSION_BUS_ADDRESS" ]] && command -v dbus-launch &>/dev/null; then
    eval "$(dbus-launch --sh-syntax)"
fi
export GPG_TTY=$(tty)

# Plugins (submodules in the dotfiles repo, found via symlink resolution)
_zsh_plugin_dir="${${(%):-%x}:A:h}/plugins"
[[ -f "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
    source "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$_zsh_plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
    source "$_zsh_plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset _zsh_plugin_dir

tm() {
    local takeover=1
    while (( $# )); do
        case "$1" in
            -a|--attach) takeover=0 ;;
            -h|--help)
                cat <<'EOF'
tm — attach to (or create) the tmux session for the current directory.

Session name: first line of ./.tmux-session, else basename of $PWD.

Usage: tm [-a|--attach] [-h|--help]
  (default)      take over: attach and detach any other client
  -a, --attach   share: attach without detaching other clients
  -h, --help     show this help
EOF
                return 0 ;;
            *) print -u2 "tm: unknown option: $1"; return 2 ;;
        esac
        shift
    done

    local name
    [[ -f .tmux-session ]] && name=$(head -n1 .tmux-session | tr -d '[:space:]')
    [[ -z "$name" ]] && name=$(basename "$PWD")

    if tmux has-session -t "=$name" 2>/dev/null; then
        if (( takeover )); then
            tmux attach-session -d -t "=$name"
        else
            tmux attach-session -t "=$name"
        fi
    else
        tmux new-session -s "$name"
    fi
}

if [[ -o login ]] && command -v fastfetch &>/dev/null; then fastfetch; fi

# direnv: per-directory environment loading (only if installed)
if command -v direnv &>/dev/null; then
    eval "$(direnv hook zsh)"
fi

# Per-host overrides
if [[ -f ~/.zshrc.local ]]; then source ~/.zshrc.local; fi
