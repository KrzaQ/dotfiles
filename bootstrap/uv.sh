#!/usr/bin/env bash
set -euo pipefail

if command -v uv &>/dev/null; then
    echo "uv is already installed: $(uv --version)"
    exit 0
fi

echo "Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

echo "uv installed successfully."
