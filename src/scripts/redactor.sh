#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"
qs_ensure_cache "widgets"

TARGET_MON="${1:-}"
SELECTED_ID="${2:-}"

if [ -n "$TARGET_MON" ] && [ -n "$SELECTED_ID" ]; then
    meander_ipc meander.redactor open "$TARGET_MON" "$SELECTED_ID"
elif [ -n "$TARGET_MON" ]; then
    meander_ipc meander.redactor open "$TARGET_MON" ""
else
    meander_ipc meander.redactor activate
fi
