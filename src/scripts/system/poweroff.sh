#!/usr/bin/env bash
# Omarchy owns the session: use its System menu action, which closes apps
# cleanly and keeps its own guards (upstream called systemd/loginctl here).
exec omarchy-system shutdown
