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

export PS1="%{%B${fg[green]}%}[%{${fg[blue]}%}%y:%n@%m:%~%{${fg[green]}%}]%b%(1j,%{${fg[green]}%}<%{%B${fg[blue]}%}%j%{%b${fg[green]}%}>%b,)%(?,,%{${fg[red]}%}{%B%?%{%b${fg[red]}%}}%b)%# "

export PS2="%{${fg[red]}%}%_> %{${fg[white]}%}"
export RPS2="%{${fg[red]}%} <%{${fg[white]}%}"

if [[ -z "$DBUS_SESSION_BUS_ADDRESS" ]] && command -v dbus-launch &>/dev/null; then
    eval "$(dbus-launch --sh-syntax)"
fi
export GPG_TTY=$(tty)

[[ -o login ]] && command -v fastfetch &>/dev/null && fastfetch

# Per-host overrides
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
