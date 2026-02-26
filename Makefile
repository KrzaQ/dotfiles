DOTFILES_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
UV := uv
INSTALL := $(UV) run $(DOTFILES_DIR)scripts/install.py

.PHONY: help install uninstall dry-run list \
        install-zsh install-vim install-git install-ssh install-gh \
        bootstrap-uv bootstrap-rbenv

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

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

install-gh: ## Install gh config
	$(INSTALL) -m gh

bootstrap-uv: ## Install uv (Python package manager)
	bash $(DOTFILES_DIR)bootstrap/uv.sh

bootstrap-rbenv: ## Install rbenv (Ruby version manager)
	bash $(DOTFILES_DIR)bootstrap/rbenv.sh
