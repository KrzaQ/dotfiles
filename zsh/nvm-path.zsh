# nvm's default Node, first on PATH, without sourcing the slow nvm.sh.
# Sourced from .zshenv and .zprofile, like ~/.local/bin there.
[[ -d ${NVM_DIR:-$HOME/.nvm}/versions/node ]] || return 0
() {
    emulate -L zsh
    local dir=${NVM_DIR:-$HOME/.nvm}
    local want=
    [[ -r $dir/alias/default ]] && want=${$(<$dir/alias/default)#v}
    # An alias that matches no version ("lts/*", "node") falls back to the newest.
    local -a bins=($dir/versions/node/v${~want}(|.*)/bin(N/nOn))
    (( $#bins )) || bins=($dir/versions/node/v*/bin(N/nOn))
    (( $#bins )) && path=($bins[1] $path)
}
