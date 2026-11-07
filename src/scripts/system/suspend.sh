#!/usr/bin/env bash
# Omarchy owns the session: use its System menu action, which closes apps
# cleanly and keeps its own guards (upstream called systemd/loginctl here).
# Omarchy locks before every suspend itself (omarchy-system-sleep-lock).
if omarchy-toggle-enabled suspend-off 2>/dev/null || omarchy-sleep-disabled 2>/dev/null; then
    notify-send -a Omarchy "Suspend is turned off" 2>/dev/null
    exit 1
fi
exec systemctl suspend
