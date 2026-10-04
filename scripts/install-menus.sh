#!/bin/bash
# Teach Omarchy's own terminal pickers about WezTerm.
#
# Optional polish. Super+Return already works from install-terminal.sh alone
# (omarchy-launch-terminal execs xdg-terminal-exec, which reads
# ~/.config/xdg-terminals.list). This only makes `omarchy default terminal
# wezterm` and `omarchy install-terminal wezterm` valid, and lists WezTerm in
# their usage text.
#
# Note: the old install script also patched omarchy-menu. This version of Omarchy
# has no terminal list in omarchy-menu at all, so there is nothing to patch there.
#
# usage: install-menus.sh --global

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

[[ $SCOPE == global ]] || die "these are Omarchy's own scripts under $PREFIX/bin; use --global"

patch_script() {
  local target="$1"
  local tmp_dir tmp
  [[ -f $target ]] || {
    warn "not found, skipping: $target"
    return 0
  }

  if grep -qF 'org.wezfurlong.wezterm.desktop' "$target"; then
    note "already patched: $target"
    return 0
  fi

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
  ' "$target" >"$tmp"

  if ! grep -qF 'org.wezfurlong.wezterm.desktop' "$tmp"; then
    rm -rf -- "$tmp_dir"
    die "could not patch $target: its shape has changed since this script was written.
    Inspect its 'case' blocks and update scripts/install-menus.sh."
  fi

  save_original "$target"
  install_patched_script "$tmp" "$target"
  rm -rf -- "$tmp_dir"
}

say "teaching Omarchy's terminal pickers about WezTerm"
patch_script "$PREFIX/bin/omarchy-default-terminal"
patch_script "$PREFIX/bin/omarchy-install-terminal"

note "omarchy-menu needs no patch in this Omarchy version"
warn "these scripts are owned by the Omarchy package; an update may revert the patch"
