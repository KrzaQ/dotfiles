# dotfiles

Personal dotfiles managed with a Python installer and Makefile.

## Setup

```sh
git clone --recursive ssh://git@forgejo.krzaq.cc/krzaq/dotfiles.git ~/code/misc/dotfiles
cd ~/code/misc/dotfiles
make bootstrap-uv   # if uv is not installed
make install
```

## Usage

```
make help            # list all targets
make install         # install all modules
make install-ssh     # install a single module
make uninstall       # remove symlinks, restore originals
make dry-run         # show what install would do
make list            # list available modules
make submodules      # init/update git submodules
make bootstrap-rust  # install the Rust toolchain (ARGS=--update to update it)
```

## Modules

| Module | What it manages |
|--------|----------------|
| zsh    | .zshrc, .zprofile, .zshenv, plugins (submodules) |
| vim    | .vimrc |
| git    | ~/.config/git/config (shared settings only) |
| ssh    | config, authorized_keys, hosts/, local/ |
| gh     | ~/.config/gh/config.yml |

## Per-host customization

Machine-specific settings go in `.local` files (never committed):

- `~/.zshrc.local` — sourced at end of .zshrc
- `~/.zprofile.local` — sourced at end of .zprofile
- `~/.gitconfig` — unmanaged, for identity and signing
- `~/.ssh/local/*.conf` — SSH overrides, loaded before hosts/
