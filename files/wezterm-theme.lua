-- managed by wezterm-omarchy
-- The Omarchy theme, as a module your own config loads.
--
-- Your ~/.config/wezterm/wezterm.lua stays yours. The installer adds one line to
-- it, immediately before your `return`:
--
--   return dofile("/…/wezterm-theme.lua")(config)
--
-- Lua allows nothing after a `return`, so that line cannot simply be appended to
-- the end of the file -- anything there would be a syntax error. It is inserted
-- just before your return instead, and your settings stay exactly where they
-- were, so you can still edit them normally.
--
-- This returns a *function* rather than a table because it has to work whatever
-- shape your config is: a wezterm.config_builder() object has to be handed back
-- to WezTerm for its settings to take effect, while a plain table is already the
-- finished article. Either way this takes what you built, applies the theme to
-- it, and gives it back.
--
-- The marker on the first line is only so `make uninstall` can tell which files
-- are safe to remove. Edit the rest freely.

return function(config)
  if type(config) ~= "table" then
    -- Nothing sensible to apply a theme to. Hand back whatever we were given
    -- rather than turning a working config into an error.
    return config
  end

  local wezterm = require("wezterm")
  local home = wezterm.home_dir or os.getenv("HOME") or ""

  ----------------------------------------------------------------------------
  -- Theme colours
  ----------------------------------------------------------------------------

  -- Omarchy generates per-theme files under the *state* directory:
  --   ~/.local/state/omarchy/current/theme/
  -- and not under ~/.config/omarchy/, which is where user *overrides* live.
  -- Reading the ~/.config path is the mistake the widely copied install script
  -- makes; it fails silently and WezTerm quietly keeps its built-in colours.
  local theme_file = home .. "/.local/state/omarchy/current/theme/wezterm.lua"

  local theme_ok, theme_colors = pcall(dofile, theme_file)
  if theme_ok and type(theme_colors) == "table" then
    -- The generated file carries the tab bar and titlebar frame alongside the
    -- palette, because they all come from the same theme. WezTerm wants them in
    -- separate settings, and rejects an unknown key *inside* colors -- with a
    -- window_frame in there it refuses the whole palette -- so lift it out.
    local frame = theme_colors.window_frame
    theme_colors.window_frame = nil

    config.colors = theme_colors

    if type(frame) == "table" then
      config.window_frame = frame
    end

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

  ----------------------------------------------------------------------------
  -- Font
  ----------------------------------------------------------------------------

  -- Inherit whatever `omarchy font set` configured. Omarchy records that choice
  -- in fontconfig, so fc-match is the source of truth -- the same thing
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
  -- Suppress missing glyph warning popups
  config.warn_about_missing_glyphs = false
  config.font_size = 9 -- matches Omarchy's own Alacritty default

  ----------------------------------------------------------------------------
  -- Appearance
  ----------------------------------------------------------------------------

  config.enable_wayland = true -- Omarchy runs Hyprland; set false to force XWayland
  config.window_decorations = "NONE"
  config.window_padding = { left = 14, right = 14, top = 14, bottom = 14 }
  config.window_close_confirmation = "NeverPrompt"
  config.default_cursor_style = "SteadyBlock"
  config.term = "xterm-256color" -- matches Omarchy's Alacritty

  -- The tab bar is deliberately left alone here. Hiding it is the more Omarchy
  -- look, but it takes a feature away rather than restyling one, so it lives in
  -- its own target and is never switched off by a theme install.

  ----------------------------------------------------------------------------
  -- Keys
  ----------------------------------------------------------------------------

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

  ----------------------------------------------------------------------------
  -- Optional add-ons
  ----------------------------------------------------------------------------

  -- Changes that alter behaviour rather than just restyling live in their own
  -- small Lua files, each with its own target, so that installing the theme
  -- never quietly takes something away:
  --
  --   make install-tabs-local     hide the tab bar (the Omarchy look)
  --   make uninstall-tabs-local   put it back
  --
  -- Each candidate is looked for next to whichever config was actually loaded
  -- (so a system-wide install can ship one for everyone) and then in the
  -- per-user config directory (so a local one still applies when a system-wide
  -- config is what loaded).
  local function addon_dirs()
    local dirs, seen = {}, {}
    local function add(dir)
      if dir and dir ~= "" and not seen[dir] then
        seen[dir] = true
        dirs[#dirs + 1] = dir
      end
    end

    add((wezterm.config_file or ""):match("^(.*)/[^/]+$"))

    -- Both locations, in the same order as the config search, so an add-on is
    -- found whichever of the two the installer wrote it to.
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

  return config
end
