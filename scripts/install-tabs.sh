#!/bin/bash
# Hide WezTerm's tab bar, for the Omarchy look.
#
# Deliberately not folded into the theme install, and deliberately not part of
# install-all: it removes a feature rather than restyling one, so it is only ever
# switched off when you ask for it by name.
#
# usage: install-tabs.sh --local|--global

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

addon="$FILES/omarchy-tabs-hidden.lua"

if [[ $SCOPE == local ]]; then
  say "hiding the WezTerm tab bar (user)"
  install_file "$addon" "$(user_wezterm_dir)/omarchy-tabs-hidden.lua"
  note "wezterm.lua picks this up on reload; undo with 'make uninstall-tabs-local'"
else
  say "hiding the WezTerm tab bar (system)"

  # wezterm.lua only looks next to the config that actually loaded, and the
  # per-user config directory. /etc/wezterm is only ever consulted because a
  # system-wide config lives there, so warn when this would go unread.
  if [[ ! -f $ETC/wezterm/wezterm.lua ]]; then
    warn "$ETC/wezterm/wezterm.lua is not installed, so nothing will read this"
    warn "run 'make install-global-config' first, or use the local target"
  fi

  install_file "$addon" "$ETC/wezterm/omarchy-tabs-hidden.lua"
  note "applies to every user; needs a WezTerm restart"
fi
