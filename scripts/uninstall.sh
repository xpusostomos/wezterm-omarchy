#!/bin/bash
# Undo an install.
#
# Only files carrying our marker are removed, so a wezterm.lua you wrote
# yourself is never deleted. Scripts we patched are restored from the pristine
# copies kept at install time.
#
# usage: uninstall.sh --local|--global

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

# MENUS_ONLY=1 removes just the menu row and helper, leaving the rest alone --
# the counterpart to install-menus.sh --local.
if [[ ${MENUS_ONLY:-0} == 1 ]]; then
  if [[ $SCOPE == local ]]; then
    say "removing WezTerm from Omarchy's default-terminal menu (user)"
    remove_file "$HOME/.local/bin/wezterm-omarchy-default-terminal"
    if command -v python3 >/dev/null 2>&1; then
      run python3 "$REPO/scripts/merge-menu-jsonc.py" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/omarchy-menu.jsonc" x --remove
    fi
  else
    say "removing the seeded menu row (system)"
    if command -v python3 >/dev/null 2>&1; then
      run python3 "$REPO/scripts/merge-menu-jsonc.py" \
        "$SKEL/.config/omarchy/extensions/omarchy-menu.jsonc" x --remove
    fi
  fi
  exit 0
fi

# TABS_ONLY=1 removes just the tab-bar add-on, leaving the rest of the install
# alone -- the counterpart to install-tabs.sh.
if [[ ${TABS_ONLY:-0} == 1 ]]; then
  if [[ $SCOPE == local ]]; then
    say "restoring the WezTerm tab bar (user)"
    remove_file "$(user_wezterm_dir)/omarchy-tabs-hidden.lua"
  else
    say "restoring the WezTerm tab bar (system)"
    remove_file "$ETC/wezterm/omarchy-tabs-hidden.lua"
  fi
  note "WezTerm brings the tab bar back on reload"
  exit 0
fi

if [[ $SCOPE == local ]]; then
  say "removing the per-user install"

  remove_file "$HOME/.config/omarchy/themed/wezterm.lua.tpl"
  remove_file "$HOME/.config/omarchy/hooks/theme-set.d/wezterm"
  remove_file "$HOME/.config/omarchy/hooks/font-set.d/wezterm"
  remove_file "$(user_wezterm_dir)/omarchy-tabs-hidden.lua"
  remove_file "$(user_applications_dir)/org.wezfurlong.wezterm.desktop"

  # The menu row and the helper its action calls.
  remove_file "$HOME/.local/bin/wezterm-omarchy-default-terminal"
  if command -v python3 >/dev/null 2>&1; then
    run python3 "$REPO/scripts/merge-menu-jsonc.py" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/omarchy-menu.jsonc" x --remove
  fi

  # Restores the list that omarchy-default-terminal wrote before we replaced it,
  # if there was one.
  restore_or_remove_file "$HOME/.config/xdg-terminals.list"

  # Put back whatever was here before. If there was no prior config, this just
  # removes ours. Done last so the generated colours go only once nothing still
  # points at the config.
  restore_or_remove_file "$(user_wezterm_dir)/wezterm.lua"

  # The colours Omarchy generated from our template. Left behind it would just
  # sit stale and unused, since nothing regenerates it once the template is gone.
  remove_file "$(generated_theme_file)"

  say "per-user install removed"
  note "any .bak.<timestamp> copies install.sh made are left in place"
else
  say "removing the system-wide install"

  # The environment file goes first. It names /etc/wezterm/wezterm.lua, and
  # WezTerm errors out and loads no config at all if that file is missing -- so
  # the reverse of the install order is what keeps every user's WezTerm working
  # at each step.
  remove_file "$ENVIRONMENT_D/99-wezterm-omarchy.conf"
  remove_file "$ETC/wezterm/wezterm.lua"

  remove_file "$PREFIX/default/wezterm/screensaver.lua"
  remove_file "$PREFIX/default/themed/wezterm.lua.tpl"
  remove_file "$PREFIX/config/wezterm/wezterm.lua"
  remove_file "$ETC/wezterm/omarchy-tabs-hidden.lua"
  remove_file "$SKEL/.local/share/applications/org.wezfurlong.wezterm.desktop"

  # The menu row seeded into the skeleton.
  if command -v python3 >/dev/null 2>&1; then
    run python3 "$REPO/scripts/merge-menu-jsonc.py" \
      "$SKEL/.config/omarchy/extensions/omarchy-menu.jsonc" x --remove
  fi

  # Patched Omarchy scripts: put the originals back.
  for patched in \
    "$PREFIX/bin/omarchy-launch-screensaver" \
    "$PREFIX/bin/omarchy-default-terminal" \
    "$PREFIX/bin/omarchy-install-terminal" \
    "$PREFIX/bin/omarchy-screensaver"; do
    restore_original "$patched" || note "no patch to undo: $patched"
  done

  # Seeds for new accounts.
  remove_file "$SKEL/.config/omarchy/hooks/font-set.d/wezterm"
  restore_or_remove_file "$SKEL/.config/xdg-terminals.list"

  say "system-wide install removed"
  warn "log out and back in so the WEZTERM_CONFIG_FILE variable is dropped"
fi
