#!/usr/bin/env bash
# Omarchy owns the session: use its System menu action, which closes apps
# cleanly and keeps its own guards (upstream called systemd/loginctl here).
if ! omarchy-hibernation-available 2>/dev/null || omarchy-sleep-disabled 2>/dev/null; then
    notify-send -a Omarchy "Hibernation is not set up" "Set it up with: omarchy setup hibernation" 2>/dev/null
    exit 1
fi
exec systemctl hibernate
