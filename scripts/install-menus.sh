#!/bin/bash
# Put WezTerm into Omarchy's own terminal pickers.
#
# This is two separate things, which is why an earlier version looked like it did
# nothing:
#
#   * The default-terminal SELECTOR is data, not code. It comes from
#     omarchy-menu.jsonc, one row per terminal, each gated by
#     `omarchy-cmd-present <terminal>`. With no wezterm row, WezTerm can never
#     appear there however the scripts are patched. Omarchy merges
#     ~/.config/omarchy/extensions/omarchy-menu.jsonc over the defaults, which is
#     the supported place to add a row and needs no root.
#
#   * The default-terminal COMMAND, omarchy-default-terminal, only accepts
#     alacritty|foot|ghostty|kitty, and lives under /usr/share/omarchy/bin which
#     comes before ~/.local/bin on PATH, so a user cannot override it. The
#     canonical `omarchy-default-terminal wezterm` therefore needs it patched:
#     root, global.
#
# So --local adds the row, and a small helper the row calls, which works without
# root. --global patches the script as well, and seeds the skeleton for new
# accounts -- where the canonical action works, so no helper is needed.
#
# usage: install-menus.sh --local|--global

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

helper_name="wezterm-omarchy-default-terminal"
merger="$REPO/scripts/merge-menu-jsonc.py"

# One row, merged into whichever menu-extensions file applies. Refuses to write
# a file that no longer parses, since the shell watches and parses this at
# startup -- a bad merge would take the whole menu with it.
merge_menu_row() { # $1 = menu extensions file, $2 = action
  local menu_file="$1" action="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found, so the menu row was skipped"
    warn "it is used only to merge one JSON entry into $menu_file;"
    warn "add the row by hand from $REPO/scripts/merge-menu-jsonc.py"
    return 0
  fi

  run python3 "$merger" "$menu_file" "$action"
  note "menu row merged into: $menu_file"
}

verify_patched() { # $1 = script
  [[ -f $1 ]] || {
    warn "not found, skipping: $1"
    return 0
  }

  if grep -qF 'org.wezfurlong.wezterm.desktop' "$1"; then
    note "already patched: $1"
    return 0
  fi

  local tmp_dir tmp
  tmp_dir="$(mktemp -d)"
  tmp="$tmp_dir/patched"

  awk '
    function indent_of(s) { return (match(s, /^[[:space:]]*/)) ? substr(s, 1, RLENGTH) : "" }

    {
      # usage text and the # omarchy:args= line
      if (index($0, "foot|ghostty|kitty") > 0 && index($0, "wezterm") == 0) {
        gsub(/alacritty\|foot\|ghostty\|kitty/, "alacritty|foot|ghostty|kitty|wezterm")
      }

      i = indent_of($0)

      # omarchy-default-terminal: desktop_id -> name
      if ($0 ~ /^[[:space:]]*kitty\.desktop\) echo "kitty" ;;[[:space:]]*$/) {
        print
        print i "org.wezfurlong.wezterm.desktop) echo \"wezterm\" ;;"
        next
      }

      # omarchy-install-terminal: package -> desktop_id
      if ($0 ~ /^[[:space:]]*kitty\) desktop_id="kitty\.desktop" ;;[[:space:]]*$/) {
        print
        print i "wezterm) desktop_id=\"org.wezfurlong.wezterm.desktop\" ;;"
        next
      }

      # omarchy-default-terminal: name -> desktop_id/name/glyph. Reuse the kitty
      # glyph so we never have to embed a Nerd Font codepoint in this repo.
      if ($0 ~ /^kitty\) desktop_id="kitty\.desktop"; name="Kitty"; glyph=/) {
        print
        line = $0
        # sub() with no target edits $0, not `line` -- pass it explicitly.
        sub(/^kitty\)/, "wezterm)", line)
        sub(/desktop_id="kitty\.desktop"/, "desktop_id=\"org.wezfurlong.wezterm.desktop\"", line)
        sub(/name="Kitty"/, "name=\"WezTerm\"", line)
        print line
        next
      }

      print
    }
  ' "$1" >"$tmp"

  if ! grep -qF 'org.wezfurlong.wezterm.desktop' "$tmp"; then
    rm -rf -- "$tmp_dir"
    die "could not patch $1: its shape has changed since this script was written.
    Inspect its 'case' blocks and update scripts/install-menus.sh."
  fi

  save_original "$1"
  install_patched_script "$tmp" "$1"
  rm -rf -- "$tmp_dir"
}

if [[ $SCOPE == local ]]; then
  say "adding WezTerm to Omarchy's default-terminal menu (user)"

  # The row's action. Baked as an absolute path rather than $HOME: the menu runs
  # actions without a shell guarantee, and this file is per-user anyway, so an
  # absolute path cannot be wrong.
  helper="$HOME/.local/bin/$helper_name"
  install_file "$FILES/$helper_name" "$helper" 755

  merge_menu_row "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/omarchy-menu.jsonc" "$helper"

  note "the menu hot-reloads that file, so WezTerm should appear straight away"
  note "undo with 'make uninstall-menus-local'"
else
  say "teaching Omarchy's terminal pickers about WezTerm (system)"

  verify_patched "$PREFIX/bin/omarchy-default-terminal"
  verify_patched "$PREFIX/bin/omarchy-install-terminal"

  # For new accounts the canonical action works, because the script above is
  # patched -- so the skeleton row needs no helper of its own.
  merge_menu_row "$SKEL/.config/omarchy/extensions/omarchy-menu.jsonc" "omarchy-default-terminal wezterm"

  warn "the patched scripts are owned by the Omarchy package; an update may revert"
  warn "them, in which case re-run this target"
fi
