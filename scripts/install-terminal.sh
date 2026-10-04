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

  # This is the one file we expect to find already written by something else
  # (omarchy-default-terminal writes it), and replacing it is the entire point of
  # this target -- so back it up and carry on rather than refusing.
  if [[ -e $dst ]] && ! is_managed "$dst"; then
    backup_file "$dst"
  fi

  run_priv install -Dm644 -- "$tmp" "$dst"
  note "installed: $dst"
  rm -rf -- "$tmp_dir"
}

if [[ $SCOPE == local ]]; then
  say "setting WezTerm as the default terminal (user)"
  write_xdg_terminals_list "$HOME/.config/xdg-terminals.list"
  note "Super+Return, xdg-terminal-exec and the Omarchy screensaver all use this"
else
  say "seeding the default-terminal preference into $SKEL (system)"
  write_xdg_terminals_list "$SKEL/.config/xdg-terminals.list"
  warn "this reaches newly created users only; run 'make install-terminal-local'"
  warn "in an existing account"
fi
