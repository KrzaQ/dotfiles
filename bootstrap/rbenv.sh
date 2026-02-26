#!/usr/bin/env bash
set -euo pipefail

if command -v rbenv &>/dev/null; then
    echo "rbenv is already installed: $(rbenv --version)"
    exit 0
fi

echo "Installing rbenv..."
git clone https://github.com/rbenv/rbenv.git ~/.rbenv

echo "Installing ruby-build plugin..."
mkdir -p ~/.rbenv/plugins
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

echo "rbenv installed. Restart your shell or run:"
echo '  eval "$(~/.rbenv/bin/rbenv init - zsh)"'
