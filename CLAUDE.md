# CLAUDE.md — Meander

Guidance for Claude Code when working on Meander (`shell/meander/`).

## What this is

Meander is **Serpantinum's desktop shell, ported to Omarchy**, shipped as one Omarchy shell **bar plugin** (`meander.bar`). Serpantinum's UI and UX are kept as they are; Omarchy is the engine underneath.

- **UI/UX source of truth:** `shell/serpantinum/` (a checkout of Serpantinum 2.4.2, `246061b`). When something looks or behaves differently from Serpantinum, Serpantinum is right and Meander is the bug -- unless `docs/parity.md` lists the difference.
- **Engine:** Omarchy (`$OMARCHY_PATH`, `/usr/share/omarchy`). Data, actions and state come from Omarchy commands, IPC and state files.
- **Runtime:** inside the running Omarchy shell (one Quickshell process). **Never start a second Quickshell**, and never `pkill quickshell`: that process is the whole Omarchy shell.

`docs/parity.md` is the module-by-module comparison with upstream (same / Omarchy-backed / shim / not ported). Keep it current with every change that touches parity.

## Layout

```
shell/meander/                 the plugin root (manifest.json must stay here)
  manifest.json                id meander.bar, entryPoints.bar = src/quickshell/MeanderBar.qml
  install.sh uninstall.sh      wrappers for bin/meander-setup
  keybinds.lua meander.lua     optional Hyprland snippets the user loads themselves
  bin/
    meander                    upstream's CLI, IPC via omarchy-shell, + Omarchy commands
    meander-setup              install / enable / disable / switch / status / doctor / update / uninstall
    meander-core               stand-in for serpantinum-core (same commands + JSON)
    meander-gamma              stand-in for serpantinum-gamma (hyprsunset)
    meander-audio              stand-in for serpantinum-audio (PipeWire filter-chain)
  config/meander/settings.json upstream defaults; meander-setup tunes them for Omarchy on first install
  src/                         upstream's src/ (MEANDER_DIR); keep its layout so upstream diffs apply
    quickshell/                the QML (root qmldir registers every type and singleton)
      MeanderBar.qml           Omarchy entry: replaces upstream Shell.qml (ShellRoot)
      omarchy/OmarchyCompat.qml  answers Omarchy's lock / osd / notifications / background / omarchy.dock IPC
      singletons/system/OmarchyHost.qml  host injection + which engines Meander owns
    scripts/                   upstream scripts; core/ holds meander-core's Python helpers
    assets/                    fonts, sounds, themes (+ Omarchy.json), languages, matugen, shaders
  docs/parity.md
```

Upstream imports are relative (`import "../"`), so the tree is relocatable. Every new QML type goes in `src/quickshell/qmldir` (a directory import of `omarchy/` from the entry did not resolve; register types there instead).

## The rules

### 1. Keep Serpantinum's code, adapt at the edges

Change upstream files only where Omarchy forces it, and say why in a comment. The Omarchy-specific code lives in the new files (`MeanderBar.qml`, `OmarchyHost.qml`, `OmarchyCompat.qml`, `scripts/core/`, `bin/meander-*`). That keeps future upstream updates mergeable: diff `shell/serpantinum` at the new upstream commit against `246061b`, apply, then re-run the sed rename (`serpantinum→meander`, `Serpantinum→Meander`, `SERPANTINUM→MEANDER`, `serp/→intro/`) on the incoming hunks.

### 2. Omarchy is the engine; a shim only where Omarchy has nothing

Order of preference: an Omarchy command or IPC (`omarchy-*`, `omarchy-shell <target> <fn>`), Omarchy state files (`~/.local/state/omarchy/...`), Quickshell services, and only then a script of our own in `src/scripts/core/` (small, stdlib only, says in its docstring why Omarchy doesn't cover it).

| Meander needs | Omarchy hook |
|---|---|
| Palette ("Omarchy" preset, default) | `~/.local/state/omarchy/current/theme/colors.toml` (+ `theme.name` watch), `ThemeBackend.parseOmarchyColors` maps it onto upstream's 22 roles (`blue` = accent) |
| Palette ("Material" preset) | `singletons/theme/Material.js` (ported from Omacale's `core/Colours.qml`): M3 tonal palettes from the Omarchy accent, mapped to the 22 roles at Catppuccin's lightness steps; settings `theme.material` (with `theme.omarchy`), `theme.materialVariant`; light/dark from `colors.toml` `mode` unless `theme.mode` says otherwise. `theme.pureBlack` is applied in `ThemeBackend.applyColorObject`, so it covers every preset |
| Theme switch | `background themeTransition` IPC -> `Commons.Color.loadColors/loadShell` + `ThemeBackend.reloadOmarchyPalette()` + wallpaper change |
| Background | `background set/transition/refresh` IPC -> `Wallpaper.setWallpaper("all", ...)`; `~/.local/state/omarchy/current/background` at start; `omarchy.followBackground` setting |
| Lock | Omarchy's `lock` IPC (`omarchy system lock`, idle, sleep-lock) -> `Lock.lock()`; PAM `omarchy-lock-password` / `omarchy-lock-fingerprint` |
| Idle | Omarchy's idle service; Meander's `idle.enabled` stays false by default |
| Notifications | Meander's NotificationServer once `omarchy.notifications` is off; Omarchy's `notifications` IPC (DND, dismissAll, act, ...) answered by `OmarchyCompat` |
| OSD | `osd show` IPC from `omarchy-osd` -> `OsdController.show` |
| Clipboard | `~/.local/state/omarchy/clipboard-history.json` (Omarchy records it); pins in `~/.cache/meander/clipboard/pins.json` |
| Brightness | `omarchy-brightness-display --no-osd N%` |
| Night light / gamma | `hyprsunset` via `meander-gamma`, `omarchy-shell nightlight refresh` |
| Power | `omarchy-system logout/reboot/shutdown`, `omarchy-toggle-enabled suspend-off`, `omarchy-sleep-disabled`, `omarchy-hibernation-available` |
| Terminal / defaults | `xdg-terminal-exec`, `omarchy-default-terminal`, `omarchy-default-browser` |
| Window corners | `ThemeBackend.borderRadius` -> `$XDG_STATE_HOME/meander/hypr.lua` (`return { radius = N }`) + `hyprctl eval "meander_apply({radius=N})"`; `meander.lua` reads the file on load (rounding = clamped radius + 2) |
| Early notifications | `manifest.json` also declares kind `service` (`MeanderService.qml`): created synchronously after the plugin scan, seconds before the async bar, and shares the `NotificationManager` singleton with it (one engine, same file URL). Ownership before the bar gets the registry comes from `shell.json` (`OmarchyHost.fileOwns`) |
| Bar hide | `~/.local/state/omarchy/toggles/bar-off` + `omarchy.bar syncHidden` |
| Panel hotkeys | host contract `summonBarWidget/hideBarWidget/isBarWidgetOpen` mapped in `MeanderBar.widgetTargets` |
| Theme picker | `themepicker/ThemePicker.qml` (registry `themes`, laid out as `wallpaper`): `meander-core themes` (`scripts/core/themes.py`: Omarchy's `omarchy-theme-switcher --print-rows` + palettes from `colors.toml`), apply `omarchy-theme-set <id>`, current from `theme.name` |
| Keyboard navigation | none upstream (pointer-only). `keynav/KeyNav.qml` (+ pure `KeyNavLogic.js`, `node tests/keynav.test.js`) walks a surface for stops on every key: PointingHand MouseAreas, `activeFocusOnTab` items, sliders, text fields; opt in/out with `keyNavTarget`, `keyNavSkip`, `keyNavActivate()`. Wired into `Main.qml` (popouts; Settings only gets the ring, `followFocus`), `bar/Bar.qml` and `dock/DockWindow.qml` (Exclusive keyboard while focused). `KeyNavState` holds bar/dock focus and the popout hand-off; IPC `meander.keys` (`meander keys ...`) |

### 3. Engines: one owner at a time

Notifications, polkit, lock, OSD, dock and background exist in both Omarchy and Meander, and two can't share one process. `OmarchyHost.owns(id)` is true only once the host has injected its registry **and** neither the Omarchy plugin nor an enabled clone of it (`clonedFrom`, e.g. Omacale's `shadow.*`) is enabled. Gate every engine on it (`Loader { active: OmarchyHost.ownsX }`, `LazyLoader` for the NotificationServer). `meander enable` hands them over in `shell.json` `disabledPlugins`; `meander disable` gives back exactly what it took (`~/.local/state/meander/install.json` `addedDisabled`, `previousBar`). Never sort or rewrite entries it didn't add.

### 4. IPC is namespaced

Every Meander `IpcHandler` target is `meander.<name>` (`meander.main`, `meander.lock`, `meander.theme`, ...), since `lock`, `osd`, `idle` are Omarchy's. Scripts call `meander_ipc` (in `caching.sh`, via `omarchy-shell`); the CLI's `cli_ipc` adds the prefix. Only `OmarchyCompat` (and `omarchy.bar syncHidden` in `MeanderBar`) answer Omarchy's own targets, and only while Meander owns that engine (a `ShellIpc` with an empty target stays silent).

### 5. Never touch what isn't ours

- Wallpaper folders are Omarchy's theme backgrounds: read only (upstream converted and deleted `.webp` sources; that code is gone -- keep it gone).
- App theming (`apptheme.py`) defaults to no apps; Omarchy themes them.
- No writes under `$OMARCHY_PATH`, no edits to the user's Hyprland files (only the optional snippets they load themselves).
- Nothing that disables the user's software (upstream's EasyEffects migration is removed).

## Dev loop

```bash
cd ~/omarchy-dotfiles/shell/meander
./install.sh --dev --no-deps          # link this checkout as ~/.config/omarchy/plugins/meander.bar
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1)
omarchy-restart-shell                  # or rely on the plugin hot reload
meander msg toggle system              # open panels over IPC (toggle; close with: meander msg close)
meander settings open theme
grim -s 0.5 /tmp/shot.png               # then look at it
qs log -p "$OMARCHY_PATH/shell" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -i meander | grep -iE "error|unavailable|not a type|TypeError|ReferenceError"
meander doctor
```

`meander disable` hands everything back to the previous bar (Omacale on this machine) without uninstalling; `meander enable` switches again. Both are live, no restart needed.

Gotchas:

- Keyboard clicks emit `MouseArea.clicked(null)`: QML can't build a MouseEvent. A handler that reads `mouse.button` must use `KeyNavState.buttonOf(mouse)` (new upstream handlers too). Don't import `QtTest` for real synthetic events.
- Restarting the shell can crash quickshell in its type loader (`QQmlImports::resolveType` → `QDir` compare) or stall it at "Configuration Loaded"; it predates Meander's keyboard work. A crash retries by itself; a stall needs that one PID killed (`omarchy-restart-shell` can't, its kill goes over IPC). Restart sparingly while the user is working.
- `omarchy-restart-shell` needs `HYPRLAND_INSTANCE_SIGNATURE`, or it stops the shell and can't start it again.
- A QML load error makes the host fall back to `omarchy.bar` ("bar option meander.bar failed to load") while Meander's engines may still be handed over: run `meander doctor`, then fix, or `meander disable`.
- Offscreen (`QT_QPA_PLATFORM=offscreen`) can't create layer-shell windows; test on Wayland.
- Don't lock the session to test the lock screen unless the user is there to type the password; use `meander lock-redactor open` for the view and `omarchy-shell lock status` for the wiring.
- `meander-audio` changes the default sink while an EQ is set; `meander-audio stop` gives it back.
- Enabling or hot-reloading the plugin can keep QML types cached from an earlier load in the same shell process: after editing QML, `omarchy-restart-shell` before trusting a screenshot (check a log line number moved if unsure).
- `jq` programs in `meander-setup` are single-quoted: no apostrophes in comments inside them.

## Licensing

AGPL-3.0-or-later, as upstream. Keep Serpantinum's credit (`THIRD_PARTY.md`, About tab, intro "Made by @ilyamiro"). Don't add fonts or assets whose licenses forbid redistribution (SF Pro, SF Mono and TT Commons Pro were removed for that reason).

## Versioning

The version is **upstream's release plus a port revision**: `<serpantinum version>-<n>` (Arch pkgrel style). `2.4.2-1` is the first Meander release on Serpantinum 2.4.2; a Meander-only change bumps the revision (`2.4.2-2`); merging a new upstream release resets it (`2.4.3-1`). If the base is past the tag, the version stays the tag's and `upstream.json` `commitsAfterTag` says how far.

It lives in `manifest.json`, `version.txt`, the fallback in `MeanderBar.qml` and `DEFAULT_VER` in `src/scripts/updater.py`; change all four together. `upstream.json` (tag, commit, commitsAfterTag, date) changes only when upstream is merged.

Tracking upstream: `meander upstream [--log]` compares `upstream.json` with Serpantinum's latest release and master (from `shell/serpantinum` -- the reference checkout -- or `$MEANDER_UPSTREAM_DIR`, else GitHub's API). To merge: `git -C ../serpantinum pull`, diff `<old commit>..<new commit>` of `src/`, apply the hunks here with the rename (see rule 1), re-check `docs/parity.md`, then update `upstream.json` and the version.

**Every version bump adds a `## X.Y.Z-N - date` entry at the top of `CHANGELOG.md` in the same commit** (Added / Changed / Fixed, `**area**: what it does for the user`), naming the upstream base when it moved.

## Git

Meander is its own repo (`AyushKr2003/meander`). Commit messages follow `feat: ...` / `fix: ...`. No Claude co-author or attribution lines. Don't bump or commit until the user has looked at the change and said ok; batch changes into one bump.
