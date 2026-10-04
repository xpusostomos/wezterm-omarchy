#!/bin/bash
# Make WezTerm the default terminal.
#
# Setting ~/.config/xdg-terminals.list is all that is needed for Super+Return:
# omarchy-launch-terminal execs xdg-terminal-exec, which reads that file. No
# patching of Omarchy's scripts is required for this to work.
#
# usage: install-terminal.sh --local|--global

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

# Written rather than copied so the marker lands in the file (it is a comment
# format, so this is harmless) and uninstall knows the file is ours to remove.
write_xdg_terminals_list() {
  local dst="$1" tmp
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  tmp="$tmp_dir/xdg-terminals.list"

  {
    printf '# Terminal emulator preference order for xdg-terminal-exec\n'
    printf '# The first found and valid terminal will be used\n'
    printf '#\n'
    printf '# %s\n' "$MARKER"
    printf 'org.wezfurlong.wezterm.desktop\n'
  } >"$tmp"

  # `replace` because this is the one file we expect to find already written by
  # something else (omarchy-default-terminal writes it), and replacing it is the
  # entire point of this target. Going through install_file means it keeps a
  # backup, and is a silent no-op when the content already matches like every
  # other file we install -- rather than rewriting on every run.
  install_file "$tmp" "$dst" 644 replace
  rm -rf -- "$tmp_dir"
}

if [[ $SCOPE == local ]]; then
  say "setting WezTerm as the default terminal (user)"
  write_xdg_terminals_list "$HOME/.config/xdg-terminals.list"

  # WezTerm's own desktop entry omits the X-TerminalArg* keys, so
  # xdg-terminal-exec drops --app-id and Omarchy's TUIs (the package installer,
  # btop, disk usage) lose the org.omarchy.terminal class they are floated by.
  # A per-user entry shadows the system one and adds the mappings.
  install_file "$FILES/org.wezfurlong.wezterm.desktop" \
    "$(user_applications_dir)/org.wezfurlong.wezterm.desktop"

  note "Super+Return, xdg-terminal-exec and the Omarchy screensaver all use this"
  note "the desktop entry is what makes Omarchy's floating TUI windows float"
else
  say "seeding the default-terminal preference into $SKEL (system)"
  write_xdg_terminals_list "$SKEL/.config/xdg-terminals.list"
  install_file "$FILES/org.wezfurlong.wezterm.desktop" \
    "$SKEL/.local/share/applications/org.wezfurlong.wezterm.desktop"
  warn "this reaches newly created users only; run 'make install-terminal-local'"
  warn "in an existing account"
fi
