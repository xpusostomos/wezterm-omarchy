-- managed by wezterm-omarchy
-- Hide WezTerm's tab bar, for the Omarchy look.
--
-- Omarchy's own terminals have no tab bar, so this matches the house style. It
-- is a separate file with its own target rather than part of the theme install
-- because it *removes a feature* rather than restyling one, and a theme install
-- should not quietly take something away:
--
--   make install-tabs-local      hide the tab bar
--   make uninstall-tabs-local    put it back
--
-- wezterm.lua loads this file when it is present and merges what it returns,
-- then lets your own ~/.config/wezterm/wezterm.lua override it.
return {
  enable_tab_bar = false,
}
