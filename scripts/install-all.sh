#!/bin/bash
# Install every target.
#
# usage: install-all.sh --local|--global

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ $SCOPE == local ]]; then
  bash "$here/install-theme.sh" --local
  bash "$here/install-font.sh" --local
  bash "$here/install-terminal.sh" --local

  say "done -- WezTerm now follows the Omarchy theme"
  note "no root was needed and nothing outside your home was touched"
  note "the tab bar is left alone; hide it with 'make install-tabs-local'"
else
  bash "$here/install-theme.sh" --global
  bash "$here/install-global-config.sh" --global
  bash "$here/install-screensaver.sh" --global
  bash "$here/install-menus.sh" --global

  # The system-wide config already themes this account, and merges whatever
  # config this account has, so only the per-user pieces the system config cannot
  # provide are installed here. The config itself is deliberately NOT installed:
  # doing so would replace this user's own wezterm.lua, and the refusal that
  # protects a hand-written config would abort the whole system install with it.
  if [[ ${GLOBAL_SKIP_USER:-0} == 1 ]]; then
    note "GLOBAL_SKIP_USER=1, so this account's per-user pieces were left alone"
    note "run 'make install-all-local' in each account that should be themed"
  else
    say "also installing the per-user pieces for $USER"
    note "your own ~/.config/wezterm/wezterm.lua is left exactly as it is"
    bash "$here/install-theme.sh" --local --hook-only
    bash "$here/install-font.sh" --local
    bash "$here/install-terminal.sh" --local
  fi

  say "done -- system-wide WezTerm theming is in place"
  note "the tab bar is left alone; hide it with 'make install-tabs-global'"
  note "log out and back in, then restart WezTerm, for the environment variable"
  warn "files under $PREFIX are owned by the Omarchy package; a future update may"
  warn "revert them, in which case re-run this target"
fi
