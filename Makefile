DOTFILES_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
UNAME_S := $(shell uname -s)
UV := uv
INSTALL := $(UV) run $(DOTFILES_DIR)scripts/install.py

.PHONY: help install uninstall dry-run list submodules \
        install-zsh install-vim install-git install-ssh install-ssh-agent install-gh install-fastfetch install-tmux install-limes \
        bootstrap-uv bootstrap-rbenv bootstrap-rust bootstrap-limes

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
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

install-gh: ## Install gh config
	$(INSTALL) -m gh

install-fastfetch: ## Install fastfetch config
	$(INSTALL) -m fastfetch

install-tmux: ## Install tmux config
	$(INSTALL) -m tmux

install-limes: ## Install limes sandbox config drop-in (opt-in)
	$(INSTALL) -m limes

submodules: ## Init/update git submodules (zsh plugins, limes)
	git submodule update --init --recursive

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
