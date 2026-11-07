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
-- curve for windows and layers. Border colours (when you turn borders back
-- on) stay the Omarchy theme's, from its hyprland.lua.

-- ── Values ──────────────────────────────────────────────────────────────────

local vars = {
  -- Serpantinum draws its panels without outlines and its windows the same.
  borderSize = 0,

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

-- ── Meander's corner radius ─────────────────────────────────────────────────
-- The shell (ThemeBackend) writes its radius to
-- $XDG_STATE_HOME/meander/hypr.lua, read here on every load, and calls
-- meander_apply() with the same table through `hyprctl eval` when it
-- changes, so a new radius lands at once and survives `hyprctl reload`.
-- Without the file (no Meander shell yet) the default radius applies.

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

local state_dir = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/meander"
local state_ok, state = pcall(dofile, state_dir .. "/hypr.lua")
local rounding = meander_rounding(state_ok and state or nil)

-- Global, so the shell can reach it through `hyprctl eval`.
function meander_apply(s)
  hl.config({ decoration = { rounding = meander_rounding(s) } })
end

-- ── General / decoration (upstream settings.lua) ────────────────────────────

hl.config({
  general = {
    border_size = vars.borderSize,
    gaps_in = vars.gapsIn,
    gaps_out = vars.gapsOut,
    float_gaps = vars.floatGaps,
    resize_on_border = true,
    -- With no border to grab, give resizing a wider invisible edge.
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
