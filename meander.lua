-- ╭─────────────────────────────────────────────────────────────────────────╮
-- │  Meander look'n'feel -- Serpantinum's Hyprland styling for Omarchy      │
-- │  Load it from ~/.config/hypr/looknfeel.lua (before your own tweaks):    │
-- │                                                                         │
-- │    pcall(dofile, os.getenv("HOME")                                      │
-- │      .. "/.config/omarchy/plugins/meander.bar/meander.lua")             │
-- │                                                                         │
-- │  pcall keeps Hyprland starting if Meander is uninstalled; dofile (not   │
-- │  require) re-reads it on every `hyprctl reload`. Anything set after     │
-- │  the dofile in looknfeel.lua wins.                                      │
-- ╰─────────────────────────────────────────────────────────────────────────╯
--
-- Ported from Serpantinum's own Hyprland config (compositors/hyprland/config/
-- settings.lua), which its author ships to match the shell: borderless
-- windows, small gaps, rounded corners, light blur, no shadow, and one springy
-- curve for windows and layers. Meander adds one thing: a thin 1px accent
-- border on the focused window, in the colour of the ring its keyboard cursor
-- draws in the shell (keynav/KeyNav.qml).

-- ── Values ──────────────────────────────────────────────────────────────────

local vars = {
  -- Serpantinum draws its windows without outlines; Meander gives the
  -- focused one a hairline of the shell's accent (its keyboard ring's
  -- colour). Unfocused windows keep a transparent border, so they stay
  -- outline-free.
  borderSize = 0,
  inactiveBorder = "rgba(00000000)",

  -- 4px between windows, 6px to the screen edge: the same distance Meander's
  -- popouts keep from the screen edge and the bar (WindowRegistry.js, 4-6px).
  gapsIn = 4,
  gapsOut = 6,
  floatGaps = 6,

  -- Corners follow Meander's own corner radius (Settings > Theme >
  -- Appearance > Border radius). Serpantinum pairs its default 10px UI radius
  -- with 12px window corners, so windows are the UI radius + 2.
  uiRadius = 10,
  roundingOffset = 2,

  -- Light blur, as upstream; Meander's own "blurred wallpaper background"
  -- draws its glass itself, so layers get no compositor blur on top.
  blurSize = 8,
  blurPasses = 2,

  shadow = false,
}

-- ── Meander's corner radius and accent ──────────────────────────────────────
-- The shell (ThemeBackend) writes its radius and accent (its primary colour,
-- the keyboard ring's) to $XDG_STATE_HOME/meander/hypr.lua, read here on
-- every load, and calls meander_apply() with the same table through
-- `hyprctl eval` when either changes, so a new value lands at once and
-- survives `hyprctl reload`. Without the file (no Meander shell yet) the
-- default radius and the Omarchy theme's border colour apply.

-- Meander clamps large radii the same way for its panels
-- (ThemeBackend.clampedBorderRadius).
local function clamped(r)
  if r <= 24 then return math.floor(r) end
  return math.floor(24 + (r - 24) ^ 0.55)
end

local function meander_rounding(s)
  s = type(s) == "table" and s or {}
  local r = tonumber(s.radius) or vars.uiRadius
  if r ~= r or r < 0 or r > 200 then r = vars.uiRadius end
  if r == 0 then return 0 end
  return clamped(r) + vars.roundingOffset
end

-- "rrggbb" from the shell, as a Hyprland colour; nil keeps the theme's.
local function meander_accent(s)
  local a = type(s) == "table" and s.accent or nil
  if type(a) ~= "string" or not a:match("^%x%x%x%x%x%x$") then return nil end
  return "rgb(" .. a .. ")"
end

local function meander_borders(s)
  local active = meander_accent(s)
  local cfg = {
    general = { col = { inactive_border = vars.inactiveBorder } },
    group = { col = { border_inactive = vars.inactiveBorder } },
  }
  if active then
    cfg.general.col.active_border = active
    cfg.group.col.border_active = active
  end
  return cfg
end

local state_dir = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/meander"
local state_ok, state = pcall(dofile, state_dir .. "/hypr.lua")
state = state_ok and state or nil
local rounding = meander_rounding(state)

-- Global, so the shell can reach it through `hyprctl eval`.
function meander_apply(s)
  hl.config({ decoration = { rounding = meander_rounding(s) } })
  hl.config(meander_borders(s))
end

-- ── General / decoration (upstream settings.lua) ────────────────────────────

hl.config({
  general = {
    border_size = vars.borderSize,
    gaps_in = vars.gapsIn,
    gaps_out = vars.gapsOut,
    float_gaps = vars.floatGaps,
    resize_on_border = true,
    -- The border is thin; give resizing a wider invisible edge.
    extend_border_grab_area = 30,
  },

  decoration = {
    rounding = rounding,
    blur = {
      enabled = true,
      size = vars.blurSize,
      passes = vars.blurPasses,
      new_optimizations = true,
    },
    shadow = {
      enabled = vars.shadow,
    },
  },
})

-- The focused window's ring (see vars.borderSize).
hl.config(meander_borders(state))

-- ── Animations (upstream settings.lua) ──────────────────────────────────────
-- One overshooting curve for everything: windows pop in from 80%, layers fade,
-- workspaces slide. The overshoot matches the spring of Meander's own
-- morphing popouts.

hl.curve("meander", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "meander", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "meander", style = "popin 80%" })
hl.animation({ leaf = "layers", enabled = true, speed = 5, bezier = "meander", style = "fade" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 5, bezier = "meander", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 5, bezier = "meander", style = "fade" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "meander" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "meander", style = "slide" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 5, bezier = "meander", style = "fade" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 5, bezier = "meander", style = "fade" })

-- ── Layers ──────────────────────────────────────────────────────────────────
-- Meander's bar, popouts (the full-screen "qs-master" surface), dock and
-- quick actions animate themselves (morph, slide, scale); a compositor fade
-- on top of that doubles the motion and lags the first frame, so they skip
-- Hyprland's layer animation. The wallpaper fades by its own transitions too.
-- The bar (meander-bar) runs its own start-up cascade and autohide slide.
hl.layer_rule({
  match = { namespace = "^(meander-bar|qs-master|qs-dock|qs-floating-edge|wallpaper-bg)$" },
  no_anim = true,
  animation = "none",
})
