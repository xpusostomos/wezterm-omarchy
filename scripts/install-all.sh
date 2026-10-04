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

  # Seed the skeleton for accounts created from now on. The theme itself already
  # reaches every account through the system-wide config; these two are the
  # per-account extras (a font hook, and WezTerm as the default terminal) that a
  # new user would otherwise have to install themselves.
  bash "$here/install-font.sh" --global
  bash "$here/install-terminal.sh" --global

  # The system-wide config already themes every account, and merges whatever
  # config an account has, so only the per-user pieces the system config cannot
  # provide are installed here. The config itself is deliberately NOT installed:
  # doing so would replace that user's own wezterm.lua, and the refusal that
  # protects a hand-written config would abort the whole system install with it.
  if [[ ${GLOBAL_SKIP_USER:-0} == 1 ]]; then
    note "GLOBAL_SKIP_USER=1, so no account's per-user pieces were touched"
    note "run 'make install-all-local' in each account that should be themed"
  else
    invoker="$(invoking_user)"

    if [[ -n $invoker ]]; then
      # Run these as the invoking user, not as root: sudo leaves $HOME at /root,
      # so running them here would put hooks in root's home and leave the real
      # account untouched. -H gives them their own HOME, so files are owned by
      # them and omarchy-theme-set writes to their state directory.
      say "also installing the per-user pieces for $invoker"
      note "run as $invoker rather than root, since sudo puts \$HOME at /root"
      run sudo -u "$invoker" -H bash "$here/install-theme.sh" --local --hook-only
      run sudo -u "$invoker" -H bash "$here/install-font.sh" --local
      run sudo -u "$invoker" -H bash "$here/install-terminal.sh" --local
    elif is_root; then
      warn "running as root, so there is no account to install the per-user pieces for"
      warn "run 'make install-all-local' as your normal user to finish that account"
    else
      say "also installing the per-user pieces for $USER"
      note "your own ~/.config/wezterm/wezterm.lua is left exactly as it is"
      bash "$here/install-theme.sh" --local --hook-only
      bash "$here/install-font.sh" --local
      bash "$here/install-terminal.sh" --local
    fi
  fi

  say "done -- system-wide WezTerm theming is in place"
  note "the tab bar is left alone; hide it with 'make install-tabs-global'"
  note "log out and back in, then restart WezTerm, for the environment variable"
  warn "files under $PREFIX are owned by the Omarchy package; a future update may"
  warn "revert them, in which case re-run this target"
fi
