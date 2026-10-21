-- managed by wezterm-omarchy
-- System-wide entry point. WEZTERM_CONFIG_FILE points here.
--
-- This applies the Omarchy theme, then loads each user's own
-- ~/.config/wezterm/wezterm.lua over the top so their settings win. Nobody's own
-- config is ever modified by a system-wide install -- unlike the per-user
-- install, which adds one line to it, there is nothing to add here: this file is
-- ours and is the thing WezTerm loads instead.

local wezterm = require("wezterm")
local home = wezterm.home_dir or os.getenv("HOME") or ""

-- The theme module. The path is substituted at install time rather than derived
-- from wezterm.config_file: with `--config-file` pointing somewhere else,
-- config_file is whatever was passed, and the module would not be found.
local config = dofile("@@THEME_MODULE@@")(wezterm.config_builder())

-- Then the user's own config, if they have one, winning over the theme's
-- defaults. This mirrors WezTerm's own search: $XDG_CONFIG_HOME/wezterm/
-- wezterm.lua when the file exists there, otherwise ~/.config/wezterm/wezterm.lua.
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

-- The _G flag is a path-independent recursion guard: if the user's config were
-- this file -- a symlink, say, or a differently spelled WEZTERM_CONFIG_FILE --
-- a path comparison would silently fail to notice and loading it would recurse
-- until the stack blows.
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
