DOTFILES_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
UNAME_S := $(shell uname -s)
UV := uv
INSTALL := $(UV) run $(DOTFILES_DIR)scripts/install.py

.PHONY: help install uninstall dry-run list submodules get-private \
        install-zsh install-vim install-git install-ssh install-ssh-private install-bin-private install-ssh-agent install-goniec-daemon install-gh install-fastfetch install-tmux install-limes \
        bootstrap-uv bootstrap-rbenv bootstrap-rust bootstrap-limes bootstrap-rosa bootstrap-goniec

help: ## Show available targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "; w = 12} { k[NR] = $$1; v[NR] = $$2; if (length($$1) > w) w = length($$1) } \
		     END { for (i = 1; i <= NR; i++) printf "  \033[36m%-*s\033[0m %s\n", w, k[i], v[i] }'

install: ## Install all modules
	$(INSTALL) $(ARGS)

uninstall: ## Remove all managed symlinks
	$(INSTALL) --uninstall $(ARGS)

dry-run: ## Show what install would do
	$(INSTALL) --dry-run

list: ## List available modules
	$(INSTALL) --list

install-zsh: ## Install zsh config
	$(INSTALL) -m zsh

install-vim: ## Install vim config
	$(INSTALL) -m vim

install-git: ## Install git config
	$(INSTALL) -m git

install-ssh: ## Install ssh config
	$(INSTALL) -m ssh

install-ssh-agent: ## Install local ssh-agent service (opt-in, prefers it over forwarded agents)
	$(INSTALL) -m ssh-agent
	systemctl --user daemon-reload
	systemctl --user enable --now ssh-agent.service
	loginctl enable-linger

install-goniec-daemon: bootstrap-goniec ## Install goniec daemon user service (opt-in)
	$(INSTALL) -m goniec-daemon
	systemctl --user daemon-reload
	systemctl --user enable --now goniec.service
	loginctl enable-linger

install-gh: ## Install gh config
	$(INSTALL) -m gh

install-fastfetch: ## Install fastfetch config
	$(INSTALL) -m fastfetch

install-tmux: ## Install tmux config
	$(INSTALL) -m tmux

install-limes: ## Install limes sandbox config drop-in (opt-in)
	$(INSTALL) -m limes

submodules: ## Init/update git submodules (private overlay too, when already fetched)
	git -C $(DOTFILES_DIR) submodule update --init --recursive
# `private` is marked `update = none`, so the line above skips it. Pull it directly
# instead -- it tracks its branch rather than the (deliberately stale) pinned SHA.
	@if [ -e $(DOTFILES_DIR)private/.git ]; then \
		git -C $(DOTFILES_DIR)private pull --ff-only; \
	fi

get-private: ## Fetch the private overlay (ssh hosts, authorized_keys, scripts; needs forgejo access)
	git -C $(DOTFILES_DIR) submodule update --init --checkout -- private
# `submodule update` checks out the pinned SHA as a detached HEAD. The overlay tracks
# its branch and is committed to directly, so land on master -- otherwise the pull below
# has no upstream, and any host added here would be committed onto a detached HEAD.
	git -C $(DOTFILES_DIR)private checkout --quiet master
	git -C $(DOTFILES_DIR)private pull --ff-only
	@echo "Fetched. Run 'make dry-run' then 'make install' to link it into ~/.ssh and ~/.local/bin."

install-ssh-private: ## Install private ssh hosts + authorized_keys (needs get-private)
	$(INSTALL) -m ssh-private

install-bin-private: ## Install private scripts into ~/.local/bin (needs get-private)
	$(INSTALL) -m bin-private

bootstrap-uv: ## Install uv (Python package manager)
	bash $(DOTFILES_DIR)bootstrap/uv.sh

bootstrap-rbenv: ## Install rbenv (Ruby version manager)
	bash $(DOTFILES_DIR)bootstrap/rbenv.sh

bootstrap-rust: ## Install Rust toolchain via rustup (ARGS=--update to update an existing one)
	bash $(DOTFILES_DIR)bootstrap/rust.sh $(ARGS)

# Depends on bootstrap-rust because lim is built with `cargo install`; rust.sh is a no-op
# when a toolchain is already present.
bootstrap-limes: bootstrap-rust ## Full limes setup (binary + config; on Linux also prereqs + daemon)
	bash $(DOTFILES_DIR)bootstrap/limes.sh
	$(INSTALL) -m limes
	bash $(DOTFILES_DIR)bootstrap/rootless-docker.sh
# `lim bootstrap` provisions the rootless daemon and image, so it is Linux-only and errors
# out elsewhere. The Seatbelt backend needs no provisioning at all, so `doctor` is both the
# right terminating step and the only "did this work" signal macOS has.
ifeq ($(UNAME_S),Linux)
	@lim=$$(command -v lim || echo "$$HOME/.cargo/bin/lim"); "$$lim" bootstrap
else
	@lim=$$(command -v lim || echo "$$HOME/.cargo/bin/lim"); "$$lim" doctor
endif

# Depends on bootstrap-rust for the same reason bootstrap-limes does: rosa is built with
# `cargo install`. Installs the binary and seeds ~/.config/rosa/config.toml; `rosa init` and
# `rosa serve` stay manual (they need a passphrase and a tty).
bootstrap-rosa: bootstrap-rust ## Install/upgrade rosa (sub-rosa secret broker) + seed config
	bash $(DOTFILES_DIR)bootstrap/rosa.sh

# Depends on bootstrap-rust: goniec is built with `cargo install`. GONIEC_REPO=<path> builds a
# development tree instead of the submodule.
bootstrap-goniec: bootstrap-rust ## Install/upgrade goniec (Zulip inboxes for agent sessions)
	bash $(DOTFILES_DIR)bootstrap/goniec.sh

# Machine-local targets (e.g. `push` to my mirrors). Untracked; see Makefile.local.
-include $(DOTFILES_DIR)Makefile.local
