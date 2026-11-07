#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"
qs_ensure_cache "lock"

case "$1" in
    --static) meander_ipc meander.lock activateStatic ;;
    --reauth) meander_ipc meander.lock restartAuth ;;
    # A plain lock is Omarchy's: it reaches Meander's lock screen through the
    # `lock` IPC Meander answers (or Omarchy's own lock while it runs), and
    # also does Omarchy's extras (1Password, keyboard layout, screensaver).
    *) exec omarchy-system-lock ;;
esac
