#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == */* ]]; then
    SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd -P)"
else
    SCRIPT_DIR="$(pwd -P)"
fi

source "$SCRIPT_DIR/caching.sh" 2>/dev/null || true

ACTION="open"
case "$1" in
    open|toggle|close) ACTION="$1"; shift ;;
esac
TAB="$1"
SUBTAB="$2"

if true; then
    meander_ipc meander.main embeddedSettings "$ACTION" "${TAB}${SUBTAB:+:$SUBTAB}"
else
    quickshell ipc call main embeddedSettings "$ACTION" "${TAB}${SUBTAB:+:$SUBTAB}" >/dev/null 2>&1
fi
