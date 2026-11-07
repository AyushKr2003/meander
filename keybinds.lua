-- ╭─────────────────────────────────────────────────────────────────────────╮
-- │  Meander keybindings -- load from ~/.config/hypr/bindings.lua with:     │
-- │    pcall(dofile, os.getenv("HOME") ..                                   │
-- │      "/.config/omarchy/plugins/meander.bar/keybinds.lua")               │
-- │  or paste the lines you want. Every key in the first part is free in a  │
-- │  stock Omarchy (check yours: omarchy menu keybindings --print).         │
-- │  Omarchy's own panel keys (SUPER + CTRL + A/B/W/...) already open       │
-- │  Meander's popouts, and SUPER + SHIFT + SPACE hides its bar.            │
-- ╰─────────────────────────────────────────────────────────────────────────╯

-- o.rebind is Omarchy's (default/hypr/helpers.lua); restated so this file
-- works when loaded on its own.
function o.rebind(keys, description, dispatcher, options)
  hl.unbind(keys)
  o.bind(keys, description, dispatcher, options)
end

-- ── Meander panels (free keys) ──────────────────────────────────────────────

o.bind("SUPER + ALT + A", "Meander launcher", "meander msg toggle launcher")
o.bind("SUPER + ALT + V", "Meander clipboard", "meander msg toggle clipboard")
o.bind("SUPER + ALT + Q", "Meander quick settings", "meander msg toggle system")
o.bind("SUPER + ALT + O", "Meander notification centre", "meander msg toggle notifications")
o.bind("SUPER + ALT + M", "Meander music", "meander msg toggle music")
o.bind("SUPER + ALT + N", "Meander network", "meander msg toggle network wifi")
o.bind("SUPER + ALT + U", "Meander volume", "meander msg toggle volume")
o.bind("SUPER + ALT + C", "Meander calendar", "meander msg toggle calendar")
o.bind("SUPER + ALT + W", "Meander wallpapers", "meander msg toggle wallpaper")
o.bind("SUPER + ALT + H", "Meander settings", "meander settings toggle")
o.bind("SUPER + ALT + Z", "Meander bar autohide", "meander msg bar autohide")
o.bind("SUPER + ALT + X", "Meander screenshot", "meander screenshot")
o.bind("SUPER + ALT + T", "Meander desktop widgets", "meander redactor")

-- ── Optional: give Omarchy's main keys to Meander ───────────────────────────
-- Remove the "--" to use them. They replace Omarchy's launcher, clipboard,
-- background picker, screenshot and power menu with Meander's.

-- o.rebind("SUPER + SPACE", "Meander launcher", "meander msg toggle launcher")
-- o.rebind("SUPER + CTRL + V", "Meander clipboard", "meander msg toggle clipboard")
-- o.rebind("SUPER + CTRL + SPACE", "Meander wallpapers", "meander msg toggle wallpaper")
-- o.rebind("PRINT", "Meander screenshot", "meander screenshot")
-- o.rebind("SHIFT + PRINT", "Meander screenshot and edit", "meander screenshot --edit")
-- o.rebind("SUPER + ESCAPE", "Meander power menu", "meander msg toggle system")
