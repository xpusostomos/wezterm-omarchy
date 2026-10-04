#!/bin/bash
# Install the Omarchy theme template and the WezTerm config that consumes it.
#
# Two mistakes from the widely copied install script live here:
#   * the template went to ~/.local/share/omarchy/default/themed, which
#     omarchy-theme-set-templates never reads
#   * the config read ~/.config/omarchy/current/theme, where Omarchy writes
#     nothing at all
#
# usage: install-theme.sh --local|--global [--hook-only]
#
# --hook-only installs just the reload hook, leaving any config alone. The
# system-wide install uses it, so that installing globally never replaces the
# account's own config.

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

template_src="$FILES/wezterm.lua.tpl"
hook_src="$FILES/theme-set.d/wezterm"

if [[ $SCOPE == local ]]; then
  if [[ $HOOK_ONLY == 1 ]]; then
    # Used by the system-wide install, where the config already comes from
    # /etc/wezterm and this account's own config must be left untouched. Only the
    # reload hook, which the system config cannot provide, is installed.
    say "installing the theme reload hook only (user)"
  else
    say "installing the WezTerm theme template and config (user)"

    INSTALL_CHANGED=0
    # Omarchy reads user templates from ~/.config/omarchy/themed, and checks them
    # before the built-in ones. Like all per-user config, this survives Omarchy
    # updates, unlike anything written under /usr/share/omarchy.
    install_file "$template_src" "$HOME/.config/omarchy/themed/wezterm.lua.tpl"
    install_wezterm_config "$(user_wezterm_dir)/wezterm.lua"
    theme_sources_changed=$INSTALL_CHANGED
  fi

  # Update-safe reload hook: omarchy-theme-set runs everything in this directory
  # after swapping the theme in. Preferred over patching omarchy's own scripts,
  # which needs root and is reverted by every Omarchy update.
  install_file "$hook_src" "$HOME/.config/omarchy/hooks/theme-set.d/wezterm" 755

  if [[ $HOOK_ONLY != 1 ]]; then
    detect_gist_leftovers
    regenerate_theme_if_needed "${theme_sources_changed:-1}"
  else
    # A system-wide install runs this inside the user's own account so their
    # colours exist straight away, but leaves an already-generated file alone.
    regenerate_theme_if_needed 0
  fi
else
  say "installing the WezTerm theme template (system)"

  # omarchy-theme-set-templates reads $OMARCHY_PATH/default/themed, so this one
  # file themes every user on the machine on the next theme change.
  INSTALL_CHANGED=0
  install_file "$template_src" "$PREFIX/default/themed/wezterm.lua.tpl"

  # Ship the config as an Omarchy user-config source too, so
  # `omarchy refresh-config wezterm/wezterm.lua` can restore it.
  install_file "$FILES/wezterm.lua" "$PREFIX/config/wezterm/wezterm.lua"

  # Generate this user's colours now rather than at the next theme change, so the
  # install has a visible effect without waiting for one.
  #
  # Skipped when running as root: $HOME is /root there, which has no Omarchy
  # theme, and generating into the real account is the per-user stage's job --
  # install-all runs that as the invoking user, which is the only way it lands in
  # the right state directory and with the right ownership.
  if is_root; then
    note "running as root, so the colours were left for the per-user stage"
  else
    regenerate_theme_if_needed "$INSTALL_CHANGED"
  fi

  warn "files under $PREFIX are owned by the Omarchy package and may be reverted"
  warn "by an update; re-run this target if that happens"
fi
