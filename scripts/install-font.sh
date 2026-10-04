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
  if [[ $HOOK_ONLY == 1 ]]; then
    # Used by the system-wide install's per-user stage, where the config already
    # comes from /etc/wezterm and the account's own config must be left alone.
    # Installing it here would replace a hand-written config, and the refusal
    # that protects one would abort the whole system install with it.
    say "installing the font hook only (user)"
  else
    say "installing WezTerm font support (user)"

    # The font is set *in* wezterm.lua, so this target has to install it.
    # Skipping it was why editing the config and running this target appeared to
    # do nothing: the hook was already identical, and the config was never
    # touched.
    install_wezterm_config "$(user_wezterm_dir)/wezterm.lua"
  fi

  install_file "$hook_src" "$HOME/.config/omarchy/hooks/font-set.d/wezterm" 755
  note "the family comes from fontconfig via fc-match, so change it with"
  note "'omarchy font set <font>'; the config supplies the fallback list"
else
  say "seeding WezTerm font support into $SKEL (system)"

  # A system install's config lives at /etc/wezterm, installed by
  # install-global-config. Refresh it here as well, so a font-side change to
  # wezterm.lua is pushed by this target rather than needing install-all-global.
  if [[ -f $ETC/wezterm/wezterm.lua ]]; then
    install_wezterm_config "$ETC/wezterm/wezterm.lua"
  fi

  install_file "$hook_src" "$SKEL/.config/omarchy/hooks/font-set.d/wezterm" 755

  # Worth being explicit about, because it is the one place where "global" cannot
  # do what the name suggests: omarchy-hook only ever reads a user's own
  # ~/.config/omarchy/hooks, so seeding /etc/skel reaches new users only.
  warn "Omarchy runs hooks from each user's own ~/.config, so this reaches newly"
  warn "created users only; run 'make install-font-local' in an existing account"
fi
