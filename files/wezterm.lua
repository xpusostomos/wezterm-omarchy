-- managed by wezterm-omarchy
-- WezTerm configuration that follows the active Omarchy theme.
--
-- Colours come from the file Omarchy regenerates on every `omarchy theme set`.
-- That file is put on WezTerm's config reload watch list below, so changing the
-- theme re-colours open windows without restarting WezTerm.
--
-- Installed by wezterm-omarchy. Edit freely -- the marker on the first line only
-- exists so that `make uninstall` can tell which files are safe to remove.

local wezterm = require("wezterm")
local config = wezterm.config_builder()

local home = wezterm.home_dir or os.getenv("HOME") or ""

--------------------------------------------------------------------------------
-- Theme colours
--------------------------------------------------------------------------------

-- Omarchy generates per-theme files under the *state* directory:
--   ~/.local/state/omarchy/current/theme/
-- and not under ~/.config/omarchy/, which is where user *overrides* live. Reading
-- the ~/.config path is the mistake the widely copied install script makes; it
-- fails silently and WezTerm quietly keeps its built-in colours.
local theme_file = home .. "/.local/state/omarchy/current/theme/wezterm.lua"

local theme_ok, theme_colors = pcall(dofile, theme_file)
if theme_ok and type(theme_colors) == "table" then
  config.colors = theme_colors

  if wezterm.add_to_config_reload_watch_list then
    -- Take the generated file under WezTerm's file watcher, so a theme change
    -- applies to already open windows.
    wezterm.add_to_config_reload_watch_list(theme_file)
  end
else
  -- Missing or broken theme (fresh install, or the template is not installed).
  -- Fall back to WezTerm's built-in colours rather than failing to load.
  wezterm.log_error(string.format(
    "wezterm-omarchy: could not load theme from %s (%s)", theme_file, tostring(theme_colors)))
end

--------------------------------------------------------------------------------
-- Font
--------------------------------------------------------------------------------

-- Inherit whatever `omarchy font set` configured. Omarchy records that choice in
-- fontconfig, so fc-match is the source of truth -- the same thing that
-- `omarchy-font-current` reads. If the lookup fails we leave config.font unset
-- and WezTerm uses its own default.
local wanted_family = ""
local ran, success, stdout = pcall(wezterm.run_child_process,
  { "fc-match", "monospace", "-f", "%{family}" })
if ran and success and type(stdout) == "string" then
  wanted_family = stdout:gsub("^%s+", ""):gsub("%s+$", "")
end
if wanted_family ~= "" then
  config.font = wezterm.font(wanted_family)
end

config.font_size = 9 -- matches Omarchy's own Alacritty default

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------

config.enable_wayland = true -- Omarchy runs Hyprland; set false to force XWayland
config.window_decorations = "NONE"
config.window_padding = { left = 14, right = 14, top = 14, bottom = 14 }
config.window_close_confirmation = "NeverPrompt"
config.default_cursor_style = "SteadyBlock"
config.term = "xterm-256color" -- matches Omarchy's Alacritty

-- The tab bar is deliberately left alone here. Hiding it is the more Omarchy
-- look, but it takes a feature away rather than restyling one, so it lives in
-- its own target and is never switched off by a theme install. See the add-ons
-- section below.

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------

local act = wezterm.action
config.keys = {
  -- Omarchy maps SUPER+C / SUPER+V to these, so terminals answer to the same
  -- chords as everything else.
  { key = "Insert", mods = "CTRL", action = act.CopyTo("Clipboard") },
  { key = "Insert", mods = "SHIFT", action = act.PasteFrom("Clipboard") },

  -- Send Shift+Return as CSI-u so TUIs such as tmux can tell it from Return
  -- without reading it as Alt+Return. Mirrors Omarchy's Alacritty config.
  { key = "Return", mods = "SHIFT", action = act.SendString("\x1b[13;2u") },
  { key = "Return", mods = "ALT|SHIFT", action = act.SendString("\x1b[13;4u") },
}

--------------------------------------------------------------------------------
-- Optional add-ons
--------------------------------------------------------------------------------

-- Changes that alter behaviour rather than just restyling live in their own
-- small Lua files, each with its own target, so that installing the theme never
-- quietly takes something away. The one that ships here:
--
--   make install-tabs-local     hide the tab bar (the Omarchy look)
--   make uninstall-tabs-local   put it back
--
-- Each candidate is looked for next to whichever config was actually loaded (so
-- a system-wide install can ship one for everyone) and then in the per-user
-- config directory (so a local one still applies when a system-wide config is
-- what loaded).
local function addon_dirs()
  local dirs, seen = {}, {}
  local function add(dir)
    if dir and dir ~= "" and not seen[dir] then
      seen[dir] = true
      dirs[#dirs + 1] = dir
    end
  end

  add((wezterm.config_file or ""):match("^(.*)/[^/]+$"))

  -- Both locations, in the same order as the config search above, so an add-on
  -- is found whichever of the two the installer wrote it to.
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then
    add(xdg .. "/wezterm")
  end
  if home ~= "" then
    add(home .. "/.config/wezterm")
  end

  return dirs
end

for _, dir in ipairs(addon_dirs()) do
  local path = dir .. "/omarchy-tabs-hidden.lua"
  local chunk = loadfile(path)
  if chunk then
    local ok, extra = pcall(chunk)
    if ok and type(extra) == "table" then
      for key, value in pairs(extra) do
        config[key] = value
      end
      if wezterm.add_to_config_reload_watch_list then
        wezterm.add_to_config_reload_watch_list(path)
      end
    elseif not ok then
      wezterm.log_error("wezterm-omarchy: add-on " .. path .. " failed: " .. tostring(extra))
    end
    break
  end
end

--------------------------------------------------------------------------------
-- Per-user overrides
--------------------------------------------------------------------------------

-- When installed system-wide, WEZTERM_CONFIG_FILE points WezTerm at this file, so
-- a user's own ~/.config/wezterm/wezterm.lua would otherwise be ignored entirely.
-- Load it and let it win over the defaults above.
--
-- Mirror WezTerm's own search for the per-user config: it looks at
-- $XDG_CONFIG_HOME/wezterm/wezterm.lua *when the file exists there* and falls
-- back to ~/.config/wezterm/wezterm.lua otherwise. Trying only the XDG path would
-- silently ignore a config sitting at the ordinary location whenever
-- XDG_CONFIG_HOME points somewhere else.
local function user_config_candidates()
  local paths = {}
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then
    paths[#paths + 1] = xdg .. "/wezterm/wezterm.lua"
  end
  if home ~= "" then
    paths[#paths + 1] = home .. "/.config/wezterm/wezterm.lua"
  end
  return paths
end

-- The _G flag is a path-independent recursion guard: if the user's config *is*
-- this file -- a symlink, say, or a differently spelled WEZTERM_CONFIG_FILE --
-- then a path comparison silently fails to notice and loading it would recurse
-- until the stack blows. The flag stops that whatever the paths look like.
local user_path, user_chunk
for _, candidate in ipairs(user_config_candidates()) do
  if not _G.__omarchy_wezterm_loading and candidate ~= wezterm.config_file then
    local chunk = loadfile(candidate)
    if chunk then
      user_path, user_chunk = candidate, chunk
      break
    end
  end
end

if user_chunk then
  _G.__omarchy_wezterm_loading = true
  local ok, user = pcall(user_chunk)
  _G.__omarchy_wezterm_loading = false

  if ok and type(user) == "table" then
    for key, value in pairs(user) do
      config[key] = value
    end
    if wezterm.add_to_config_reload_watch_list then
      wezterm.add_to_config_reload_watch_list(user_path)
    end
  elseif not ok then
    wezterm.log_error(string.format(
      "wezterm-omarchy: user config %s failed: %s", user_path, tostring(user)))
  end
end

return config
