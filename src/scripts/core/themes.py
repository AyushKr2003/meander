#!/usr/bin/env python3
"""meander-core themes: the Omarchy themes for Meander's theme picker.

    themes            one JSON object: {current, themes: [...]}

Each theme is {id, name, preview, thumb, mode, colors}. The rows (preview
image and its cached thumbnail) are Omarchy's own, from
`omarchy-theme-switcher --print-rows`, the same list Omarchy's picker shows;
what Omarchy doesn't hand out is each theme's palette, so it is read here from
the theme's colors.toml (user themes first, as `omarchy-theme-dir` does).
`colors` is [background, foreground, accent, red, yellow, green, blue,
magenta], missing ones left out. Applying a theme is `omarchy-theme-set <id>`.
"""
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
OMARCHY = os.environ.get("OMARCHY_PATH") or "/usr/share/omarchy"
USER_THEMES = os.path.join(HOME, ".config/omarchy/themes")
SYS_THEMES = os.path.join(OMARCHY, "themes")
CURRENT = os.path.join(HOME, ".local/state/omarchy/current/theme.name")
KEYS = ["background", "foreground", "accent", "red", "yellow", "green", "blue", "magenta"]
LINE = re.compile(r'^\s*([A-Za-z0-9_]+)\s*=\s*"?(#[0-9A-Fa-f]{6,8})"?')
MODE = re.compile(r'^\s*mode\s*=\s*"(\w+)"')


def theme_dir(tid):
    user = os.path.join(USER_THEMES, tid)
    return user if os.path.isdir(user) else os.path.join(SYS_THEMES, tid)


def palette(tid):
    colors, mode = {}, "dark"
    try:
        with open(os.path.join(theme_dir(tid), "colors.toml")) as f:
            for line in f:
                m = LINE.match(line)
                if m:
                    colors.setdefault(m.group(1), m.group(2))
                    continue
                m = MODE.match(line)
                if m:
                    mode = m.group(1)
    except OSError:
        pass
    return [colors[k] for k in KEYS if k in colors], mode


def title(tid):
    # omarchy-theme-list's display name: tokyo-night -> Tokyo Night
    return " ".join(w[:1].upper() + w[1:] for w in tid.split("-"))


def main():
    try:
        out = subprocess.run(["omarchy-theme-switcher", "--print-rows"], capture_output=True,
                             text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        out = ""
    themes = []
    for row in out.splitlines():
        parts = row.split("\t")
        if not parts or not parts[0]:
            continue
        preview = parts[0]
        thumb = parts[1] if len(parts) > 1 and parts[1] else preview
        tid = os.path.splitext(os.path.basename(preview))[0]
        colors, mode = palette(tid)
        themes.append({"id": tid, "name": title(tid), "preview": preview, "thumb": thumb,
                       "mode": mode, "colors": colors})
    try:
        with open(CURRENT) as f:
            current = f.read().strip()
    except OSError:
        current = ""
    json.dump({"current": current, "themes": themes}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
