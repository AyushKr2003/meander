# Changelog

What changed in each version of Meander, newest first. Versions are the ones in `manifest.json`.

Meander's version is the Serpantinum release it is built on plus a port revision: `2.4.2-1` is the first Meander release on Serpantinum 2.4.2, `2.4.2-2` a Meander-only change on the same base, and `2.4.3-1` the first release after merging Serpantinum 2.4.3. `upstream.json` holds the exact upstream commit; `meander upstream` shows how far behind Serpantinum's latest release and master it is.

## 2.4.2-2 - 2026-11-07

Upstream base: unchanged (Serpantinum v2.4.2 +10 commits, `246061b`).

### Added
- **keyboard**: full keyboard mode for every popout: arrows or h/j/k/l move to the nearest control, Tab walks them in reading order, Enter/Space clicks, Menu/Shift+F10 right-clicks, Left/Right change a slider, Ctrl+Tab goes to the next popout. An accent focus ring follows the cursor; moving the mouse hides it
- **keyboard**: bar focus (`meander keys bar`, SUPER + CTRL + 0 in `keybinds.lua`) and dock focus (`meander keys dock`, Ctrl+Tab from the bar): drive the bar or dock from the keyboard; a module that opens a popout hands the keyboard to it, Escape gives it back
- **keyboard**: `meander keys open <panel>` opens a popout with the cursor already on
- **keyboard**: Settings shows a focus ring on the focused control, and Enter steps into a page's controls
- **themes**: a theme picker (`meander msg toggle themes`, SUPER + ALT + P in `keybinds.lua`, optional rebinds of Omarchy's theme keys): Omarchy's themes in the wallpaper picker's carousel, with each theme's palette, search, and apply on Enter or click

### Fixed
- **buttons**: Enter on a focused button did nothing (the click handler got no mouse event and threw)
- **settings**: its Ctrl+Tab, Ctrl+K and Ctrl+Q shortcuts stayed active while Settings was closed, taking those keys from the other popouts

## 2.4.2-1 - 2026-11-07

Upstream base: Serpantinum v2.4.2 +10 commits (`246061b`), master at the time.

First release: Serpantinum 2.4.2 ported to Omarchy as the `meander.bar` bar plugin. See [docs/parity.md](docs/parity.md) for the module-by-module comparison.

### Added
- **shell**: Serpantinum's whole desktop inside the Omarchy shell -- bar and morphing popouts, quick settings, music with lyrics and equalizer, notification centre, launcher, clipboard, dock, desktop widgets and their editor, lock screen and its editor, wallpaper engine, screenshot and recording overlay, floating quick actions, digital wellbeing, blue light filter, settings in 23 languages
- **theme**: an "Omarchy" colour preset, the default, that follows the current Omarchy theme live; Serpantinum's palettes and Matugen stay available
- **theme**: a "Material" preset: a Material 3 scheme generated from the Omarchy accent (as in Omacale), following theme switches and the theme's light/dark mode, with nine scheme variants (Tonal spot, Vibrant, Expressive, Fidelity, Content, Neutral, Monochrome, Rainbow, Fruit salad) under Settings > Theme > Appearance > Material scheme
- **theme**: Pure black background (Settings > Theme > Appearance): black panels with any dark palette, for OLED screens
- **omarchy**: Meander answers Omarchy's own `lock`, `osd`, `notifications`, `background` and `omarchy.dock` IPC, so `omarchy system lock`, the idle lock, the brightness keys, `omarchy toggle notification silencing`, `omarchy theme set` and `omarchy theme bg next` all reach it
- **omarchy**: Omarchy's panel hotkeys (SUPER + CTRL + A/B/W/...) open Meander's popouts, and SUPER + SHIFT + SPACE hides its bar
- **installer**: `./install.sh` installs the missing packages, the plugin, its commands and Omarchy-tuned settings, and makes Meander the bar; `meander enable / disable / switch / status / doctor / update / uninstall`. Every change to `shell.json` is recorded and undone exactly
- **meander-core**: system usage, brightness, keyboard locks, monitors, screen time, launcher ranking and file search, and the clipboard over Omarchy's history, with the same commands and output as Serpantinum's Rust core
- **meander-gamma**: the blue light filter and its sunrise/sunset schedule on Omarchy's hyprsunset
- **meander-audio**: equalizer, balance, mono, channel swap and dynamic range modes on PipeWire's filter-chain
- **keybinds**: optional `keybinds.lua` (keys free in a stock Omarchy)
- **look'n'feel**: optional `meander.lua`, Serpantinum's own Hyprland styling: borderless windows, 4/6px gaps (the distance Meander's popouts keep from the edge), light blur, no shadow, a wider resize edge, its springy pop-in animations, and no compositor fade on Meander's self-animating surfaces. Window corners follow Meander's corner radius (radius + 2, so the default 10 gives upstream's 12) and change live when you change it in Settings
- **startup**: a small service entry starts the notification server before the rest of the bar has loaded, so `omarchy restart shell` usually finds notifications ready (it waits only 2s; with Meander's size it still misses the window now and then)
- **brand**: Meander name and logo
- **versioning**: versions follow upstream (`<serpantinum version>-<port revision>`), `upstream.json` records the base commit, and `meander upstream [--log]` reports how far behind Serpantinum's release and master Meander is

### Changed
- **IPC**: every Meander IPC target is namespaced `meander.*`
- **power**: logout, reboot and shutdown go through `omarchy-system`; suspend and hibernate honour Omarchy's guards
- **lock**: authenticates with Omarchy's PAM services (`omarchy-lock-password`, `omarchy-lock-fingerprint`)
- **idle**: Omarchy's idle service is in charge; Meander's idle engine is opt-in
- **app theming**: off by default (Omarchy themes apps); opt in per app under Settings > Theme > App theming
- **dock**: starts with your Omarchy terminal, browser and file manager
- **launcher**: runs `>` commands in Omarchy's terminal (`xdg-terminal-exec`)
- **first launch**: starts from the current Omarchy background
- **battery**: low-battery warnings stay Omarchy's (`omarchy.batteryAlerts` turns Meander's back on)

### Fixed (upstream bugs)
- **wallpapers**: thumbnailing no longer converts `.webp` wallpapers to `.jpg` and deletes the originals
- **wallpapers**: the thumbnailer reads the wallpaper folder setting instead of always using `~/Pictures/Wallpapers`
- **bar**: the focus-mode launcher button opens the launcher
- **intro**: the tutorial's `meander open/close <panel>` steps work

### Removed
- Niri, Sway and Mango configs, NixOS modules, packaging, website, install telemetry, the Ski file manager installer, the EasyEffects migration, and the SF Pro, SF Mono and TT Commons Pro fonts (not redistributable)
