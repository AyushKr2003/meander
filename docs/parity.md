# Parity with Serpantinum

Meander 2.4.2-2 against Serpantinum 2.4.2 (+10 commits, `246061b`), module by module. Run `meander upstream --log` to see what upstream has added since.

- **Same**: upstream's code and UI, unchanged apart from the rename.
- **Omarchy**: same UI, backed by Omarchy instead of upstream's own service.
- **Shim**: same UI and the same command line, served by Meander's own small
  script where Omarchy has nothing (`meander-core`, `meander-gamma`,
  `meander-audio`).

## Shell modules (`src/quickshell/`)

| Module | Status | Notes |
|---|---|---|
| Bar (`bar/`, top or side, every face: workspaces ×3, clock ×4, media, info, weather, tray, keyboard, Wi-Fi, Bluetooth, volume, battery, system monitor, visualiser, focus) | Same | Hidden by `omarchy toggle bar`; tells the host its edge and size |
| Popouts (`Main.qml`: network, volume, settings, calendar, wallpaper, music, notifications, quick settings) | Same | Also opened by Omarchy's panel hotkeys (`summonBarWidget`) |
| Settings app (`guide/`, every tab) | Same | Theme tab gains the "Omarchy" preset (default) |
| Theme presets, Matugen, fonts, opacity, blur, liquid glass | Same | + "Omarchy" preset from the live `colors.toml`, + "Material" preset (M3 scheme from the Omarchy accent, 9 variants, from Omacale), + Pure black background |
| App theming (`apptheme.py`, 50 apps) | Same, opt-in | Default list empty: Omarchy themes apps itself |
| Launcher (apps, files, emoji, calculator, converter, web search) | Same | Ranking and file search from `meander-core` |
| Clipboard | Omarchy | Omarchy's clipboard history; pins kept by Meander |
| Notifications (server, popups, centre, types, sounds) | Same, handed over | Runs once `omarchy.notifications` is off; answers Omarchy's `notifications` IPC (DND, dismiss, act, history) |
| OSD (volume, mic, brightness, caps/num lock, airplane) | Same, handed over | Answers Omarchy's `osd show` (brightness keys); other Omarchy OSD messages become a short notification |
| Polkit agent | Same, handed over | Runs once `omarchy.polkit` is off |
| Lock screen + lock layout editor | Same, handed over | Reached through Omarchy's `lock` IPC; PAM service `omarchy-lock-password` / `omarchy-lock-fingerprint` |
| Idle (`idle/`) | Same, opt-in | Omarchy's idle service is in charge by default (upstream defaulted to on) |
| Dock + app picker + menus | Same, handed over | Default apps: your Omarchy terminal, browser, file manager |
| Desktop widgets + widget editor (clock, weather, music, usage, notes, GitHub, image, text, user, battery, visualiser) | Same | |
| Wallpaper engine (images, video, transitions) + picker (local, favourites, history, colour filter, web search) | Same, Omarchy-fed | Follows Omarchy's background; picker folder is the current theme's backgrounds |
| Screenshot / recording overlay (region, window, screen, edit, OCR, QR, audio) | Same | |
| Floating quick actions (calculator, notes, timer, draw, system usage, dock) | Same | |
| Digital wellbeing (day/week/month, heatmap, limits, overlay) | Shim | `meander-core screentime` (SQLite, Hyprland events) |
| First launch intro + tutorial | Same | Starts from Omarchy's background; `meander open/close` now routed |
| Weather, location, calendar | Same | |
| Media (MPRIS, lyrics, art, visualiser) | Same | |
| Translations (23 languages) | Same | |
| Theme picker (`themes` popout) | Meander only | Omarchy themes in the wallpaper picker's carousel (same cards, skew, motion, top bar); rows from `omarchy-theme-switcher --print-rows`, palettes from each `colors.toml` (`meander-core themes`), applied with `omarchy-theme-set` |
| Keyboard navigation (popouts, bar focus, dock focus) | Meander only | Upstream is pointer-only. A cursor over each surface's controls (arrows/hjkl spatial, Tab reading order, Enter click, Menu right click, sliders on arrows, Ctrl+Tab between panels); Settings keeps upstream's keys and gains a visible focus ring and Enter into the page |

## Native helpers

| Upstream | Meander | Difference |
|---|---|---|
| `serpantinum-core` (Rust daemon) | `meander-core` (bash + stdlib Python) | Same commands and JSON. Caps/Num Lock are polled from `/sys/class/leds` (upstream read `/dev/input`). No `org.freedesktop.ScreenSaver` server: app idle inhibitors are Omarchy's idle service's job. Sway/Niri/Mango feeds are no-ops (Omarchy is Hyprland) |
| `serpantinum-gamma` (Wayland gamma daemon) | `meander-gamma` → `hyprsunset` | Shares Omarchy's night light state. Temperature only, applied to all outputs (no per-output values, brightness, gamma or inversion) |
| `serpantinum-audio` (PipeWire processor) | `meander-audio` → PipeWire filter-chain | 10-band EQ, balance, mono, swap; dynamics via swh-plugins' SC4 compressor. The dynamic EQ switch is accepted but has no effect yet. Changes restart the chain (a short gap), upstream updated live |
| `serpantinumd` (launcher daemon) | — | The Omarchy shell is the process; the bar starts the screen-time tracker |
| `serpantinum` CLI | `meander` CLI | Same commands; IPC goes through `omarchy-shell`; `kill` = `disable`, `restart` restarts the Omarchy shell; adds `enable`, `disable`, `switch`, `status`, `doctor`, `update`, `uninstall`, `open/close/toggle` |
| Power scripts (systemd/loginctl/...) | `omarchy-system logout/reboot/shutdown` | Omarchy's guards for suspend and hibernate |

## Not carried over

- Niri, Sway and Mango configs, NixOS modules, AUR/Fedora/Void packaging, the
  website, install telemetry and the Ski file manager installer: Omarchy is
  Arch + Hyprland, and Omarchy ships its own file manager.
- SF Pro, SF Mono and TT Commons Pro fonts (not redistributable).
- The EasyEffects migration, which disabled EasyEffects' autostart.

## Upstream bugs fixed on the way

- `ClickButton`/`IconButton` Enter called their MouseArea's `clicked({button})`; the
  object arrives as null, so the handler threw and Enter did nothing.
- Settings' shortcuts (Ctrl+Tab, Ctrl+K, Ctrl+Q) stayed live while it was hidden in
  the popout cache, colliding with other popouts' keys.

- Wallpaper thumbnailing converted `.webp` sources to `.jpg` and deleted the
  originals in the wallpaper folder (it would have deleted Omarchy theme files).
- The thumbnailer ignored the `wallpaperDir` setting (read an unset `$srcdir`).
- The focus-mode bar's launcher button sent `applauncher`, which nothing handled.
- The intro tutorial ran `meander open/close <panel>`, which the CLI didn't route.

## Verified on a live Omarchy (2.4.2-1)

Bar, quick settings, volume, calendar + weather, music + equalizer, network,
wallpaper picker, settings (welcome, theme, wellbeing), launcher, clipboard,
notifications (server + popup), OSD from `omarchy-osd`, polkit dialog, screenshot
overlay, widget and lock layout editors, theme switch Jade Horse → Gruvbox → back,
EQ sink on and off, enable/disable round trip of `shell.json` (the same JSON
afterwards, list order included), `meander-core` commands, screen-time tracking.

Not exercised live: an actual lock/unlock (needs the user's password),
recording, OCR/QR, EQ dynamics (swh-plugins not installed), Matugen app theming
(matugen not installed).
