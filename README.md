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
make get-private     # fetch the private overlay (see below)
make bootstrap-rust  # install the Rust toolchain (ARGS=--update to update it)
```

## Modules

| Module | What it manages |
|--------|----------------|
| zsh    | .zshrc, .zprofile, .zshenv, plugins (submodules) |
| vim    | .vimrc |
| git    | ~/.config/git/config (shared settings only) |
| ssh    | ~/.ssh/config, local/ |
| ssh-private | authorized_keys, hosts/ — from the private overlay, skipped when absent |
| gh     | ~/.config/gh/config.yml |

## Private overlay

Host definitions and `authorized_keys` live in a separate private repo, wired in as a
submodule at `private/`. It is marked `update = none`, so `git clone --recursive` and
`make submodules` skip it — this repo clones and installs fine without any access to it,
and `~/.ssh/config` tolerates the resulting empty `Include hosts/*` glob.

```sh
make get-private   # opt in: clones the overlay, then tracks its branch
make install       # ssh-private is picked up automatically once present
```

The submodule's pinned SHA is deliberately **not** maintained (`ignore = all`); the overlay
always tracks its own branch, so there is no gitlink bump to commit here on every host
change. `make get-private` and `make submodules` both pull it forward.

## Per-host customization

Machine-specific settings go in `.local` files (never committed):

- `~/.zshrc.local` — sourced at end of .zshrc
- `~/.zprofile.local` — sourced at end of .zprofile
- `~/.gitconfig` — unmanaged, for identity and signing
- `~/.ssh/local/*.conf` — SSH overrides, loaded before hosts/
- `~/.config/limes/config.d/local-data-root.toml` — written by `make bootstrap-limes` on a
  machine whose `$HOME` can't hold the docker data-root (an encrypted home); points limes
  at `/var/lib/limes/$USER` instead
