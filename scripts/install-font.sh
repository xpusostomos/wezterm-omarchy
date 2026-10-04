#!/bin/bash
# Install the hook that makes WezTerm follow `omarchy font set`.
#
# usage: install-font.sh --local|--global

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

hook_src="$FILES/font-set.d/wezterm"

if [[ $SCOPE == local ]]; then
  say "installing the font hook (user)"
  install_file "$hook_src" "$HOME/.config/omarchy/hooks/font-set.d/wezterm" 755
  note "wezterm.lua reads the font from fontconfig, so this only prompts a reload"
else
  say "seeding the font hook into $SKEL (system)"
  install_file "$hook_src" "$SKEL/.config/omarchy/hooks/font-set.d/wezterm" 755

  # Worth being explicit about, because it is the one place where "global" cannot
  # do what the name suggests: omarchy-hook only ever reads a user's own
  # ~/.config/omarchy/hooks, so seeding /etc/skel reaches new users only.
  warn "Omarchy runs hooks from each user's own ~/.config, so this reaches newly"
  warn "created users only; run 'make install-font-local' in an existing account"
fi
