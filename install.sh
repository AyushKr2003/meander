#!/usr/bin/env bash
# Install Meander on Omarchy: ./install.sh [--dev] [--no-deps] [--no-enable]
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bin/meander-setup" install "$@"
