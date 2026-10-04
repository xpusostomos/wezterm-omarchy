-- managed by wezterm-omarchy
-- WezTerm config used as the host for Omarchy's screensaver.
--
-- Omarchy's "screensaver" is a fullscreen terminal running `omarchy-screensaver`,
-- which animates Omarchy's branding with ttfx on a black background. This config
-- removes every trace of chrome so only the animation is visible.
--
-- Not a theme-tracking config: the screensaver is deliberately black regardless
-- of the active theme, exactly as Omarchy's Alacritty/Ghostty/Kitty configs are.

local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.colors = {
  foreground = "#a9b1d6",
  background = "#000000",
  cursor_bg = "#000000",
  cursor_fg = "#000000",
  cursor_border = "#000000",
}

config.font_size = 18
config.enable_wayland = true

config.window_decorations = "NONE"
config.enable_tab_bar = false
config.window_background_opacity = 1.0
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
config.window_close_confirmation = "NeverPrompt"
config.default_cursor_style = "SteadyBlock"

return config
