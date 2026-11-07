<div align="center">
  <img src="src/assets/logo.svg" alt="Meander" width="120" />
  <h1>Meander</h1>
  <p>A <a href="https://github.com/ilyamiro/serpantinum">Serpantinum</a>-style desktop shell for <a href="https://omarchy.org">Omarchy</a>.</p>
</div>

Meander brings Serpantinum's whole desktop to Omarchy: the modular bar with its
morphing popouts, the quick settings panel, music player with lyrics and a
10-band equalizer, notification centre, launcher (apps, files, emoji,
calculator), clipboard, dock, desktop widgets and their layout editor, the
lock screen and its layout editor, wallpaper engine with transitions and video
wallpapers, screenshot and recording overlay (OCR, QR), floating quick actions
(calculator, notes, timer, draw, system usage), digital wellbeing with daily
limits, a blue light filter with a day/night schedule, and the full settings
app in 23 languages.

It runs **inside the Omarchy shell** as an Omarchy bar plugin (`meander.bar`),
in the same Quickshell process. Omarchy stays the engine: its themes colour
Meander live, its background follows `omarchy theme set` and `omarchy theme bg
next`, its idle service and `omarchy system lock` drive Meander's lock screen,
its clipboard history fills Meander's clipboard panel, its brightness keys
show Meander's OSD, and every `omarchy` command keeps working.

## Install

```bash
git clone https://github.com/AyushKr2003/meander.git
cd meander
./install.sh
```

The installer:

1. installs the few packages Meander needs beyond a stock Omarchy (`matugen`,
   `pavucontrol`, `satty`, `wf-recorder`, `playerctl`, `swh-plugins`, ...),
   all from Arch's repos;
2. copies the plugin to `~/.config/omarchy/plugins/meander.bar` and links its
   commands (`meander`, `meander-core`, `meander-gamma`, `meander-audio`,
   `meander-setup`) into `~/.local/bin`;
3. writes `~/.config/meander/settings.json` with Omarchy defaults (the
   Omarchy colour preset, your Omarchy font, your default terminal, browser
   and file manager in the dock, wallpapers from the current Omarchy theme);
4. makes Meander the Omarchy bar and hands it the jobs Omarchy also does, by
   turning off `omarchy.notifications`, `omarchy.polkit`, `omarchy.lock`,
   `omarchy.osd`, `omarchy.dock` and `omarchy.background` (and any enabled
   clone of them) in `~/.config/omarchy/shell.json`.

Every change to `shell.json` is recorded, and `meander disable` puts back
exactly what was there before. `./install.sh --dev` links the checkout instead
of copying it, `--no-deps` skips packages, and `--no-enable` installs without
switching.

### Keybindings (optional)

Omarchy's own panel keys already open Meander's popouts (SUPER + CTRL + A
audio, B bluetooth, W Wi-Fi, ...), and SUPER + SHIFT + SPACE hides its bar.
For Meander's own panels, load `keybinds.lua` from
`~/.config/hypr/bindings.lua`:

```lua
pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/meander.bar/keybinds.lua")
```

It binds SUPER + ALT + A (launcher), V (clipboard), Q (quick settings),
O (notifications), M (music), N (network), U (volume), C (calendar),
W (wallpapers), P (theme picker), H (settings), Z (bar autohide), X (screenshot) and T
(desktop widgets), all free in a stock Omarchy. Commented `o.rebind` lines
at the bottom hand SUPER + SPACE, SUPER + CTRL + V, SUPER + CTRL + SPACE,
SUPER + CTRL + T (theme menu), PRINT and SUPER + ESCAPE to Meander too.

The theme picker (`meander msg toggle themes`) shows Omarchy's themes the way
the wallpaper picker shows wallpapers: ← → (or h l, the wheel) to browse,
Enter or a click to apply (`omarchy-theme-set`), `/` to search. It stays open,
so you can try the next one.

### Keyboard navigation

Every popout, the bar and the dock can be driven without the mouse. The
cursor appears on the first key press (or right away when the keyboard opened
the panel) and disappears when you move the mouse.

| Key | Action |
|---|---|
| arrows, `h` `j` `k` `l` | Move to the nearest control in that direction |
| `Tab` / `Shift + Tab` | Next / previous control in reading order |
| `Home` / `End` | First / last control |
| `Enter` / `Space` | Activate (a click) |
| `Menu` / `Shift + F10` | Secondary action (a right click: tray and dock menus, quick-setting pages) |
| `←` `→` on a slider | Change it by 5% (`Shift`: by one step); `↑` `↓` on a vertical one |
| `Ctrl + Tab` / `Ctrl + Shift + Tab` | Next / previous popout; on the bar, go to the dock and back |
| `Escape` | Close the popout, or give the keyboard back from the bar / dock |

`keybinds.lua` binds SUPER + CTRL + 0 to bar focus (`meander keys bar`). From
there, a module that opens a popout hands the keyboard to it. Settings keeps
its own keys (arrows and Tab change tabs, `/` searches); `Enter` steps into the
page's controls, `↑` `↓` walk them, and `Escape` steps back out.

`meander.lua` is Serpantinum's Hyprland look (borderless windows, 4/6px gaps,
light blur, no shadow, its pop-in animations), with window corners that follow
Meander's corner radius live. Load it from `~/.config/hypr/looknfeel.lua`
(also optional):

```lua
pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/meander.bar/meander.lua")
```

## Commands

```text
meander enable | disable | switch [omarchy|meander]
meander status | doctor | update | uninstall [--purge]
meander upstream [--log] # how far behind Serpantinum's release and master it is
meander msg toggle <launcher|clipboard|system|notifications|music|network|volume|calendar|wallpaper|themes>
meander settings [tab]
meander keys bar|dock|off   # bar / dock take the keyboard (Escape gives it back)
meander keys open <panel>   # open a popout with the keyboard cursor on
meander screenshot [--edit|--full|--record|--ocr|--qr]
meander lock | redactor | lock-redactor
meander config get|set|dump|path|edit
meander info|set|trigger ...
meander restart          # restarts the Omarchy shell, which reloads Meander
```

## How it maps onto Omarchy

| Meander | Backed by |
|---|---|
| Colours (the default "Omarchy" preset) | the current theme's `colors.toml`, live on every `omarchy theme set`; Serpantinum's 80+ palettes and Matugen stay available |
| Colours ("Material" preset) | a Material 3 scheme generated from the Omarchy accent (Tonal spot, Vibrant, Expressive, ...), light or dark as the theme is; plus a Pure black background option for any dark palette |
| Wallpaper | Meander's engine draws Omarchy's current background, with Serpantinum's transitions, on every theme or background change |
| Lock screen | Meander's lock, through Omarchy's `lock` IPC (`omarchy system lock`, idle, sleep), authenticating with Omarchy's own PAM services |
| Idle | Omarchy's idle service (`shell.json` `idle`); Meander's own idle engine stays opt-in |
| Notifications, polkit, OSD, dock | Meander's, once Omarchy's are handed over; Omarchy's `notifications`, `osd` and `omarchy.dock` IPC still answer |
| Clipboard | Omarchy's clipboard history, with Meander's pins |
| Brightness | `omarchy-brightness-display` |
| Blue light filter | `hyprsunset`, Omarchy's night light (`meander-gamma`) |
| Equalizer, balance, mono, swap, dynamics | PipeWire's filter-chain (`meander-audio`), only while something is set |
| Power menu | `omarchy-system` logout / reboot / shutdown, with Omarchy's suspend and hibernate guards |
| System usage, screen time, launcher ranking | `meander-core` (stdlib Python and bash) |

## Uninstall

```bash
meander uninstall          # or ./uninstall.sh; add --purge to drop settings too
```

## Versions

Meander's version is the Serpantinum release it is built on plus a port
revision: `2.4.2-1` is the first Meander release on Serpantinum 2.4.2. The
exact upstream commit is in `upstream.json`, and `meander upstream` compares
it with Serpantinum's latest release and master.

## Credits and license

Meander is a fork of [Serpantinum](https://github.com/ilyamiro/serpantinum)
2.4.2 by Illia Miroshnichenko ([@ilyamiro](https://github.com/ilyamiro)) and its
contributors, ported to Omarchy by [@AyushKr2003](https://github.com/AyushKr2003).
Like Serpantinum it is licensed under the GNU Affero General Public License
version 3 or later; see [LICENSE.md](LICENSE.md) and [THIRD_PARTY.md](THIRD_PARTY.md).
