#!/usr/bin/env bash
# Remove Meander and give the desktop back to Omarchy: ./uninstall.sh [--purge]
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bin/meander-setup" uninstall "$@"
