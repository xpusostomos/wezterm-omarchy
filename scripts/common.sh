#!/bin/bash
# Shared helpers for the wezterm-omarchy installers.
#
# Every path is overridable from the environment so the whole install can be
# exercised against a throwaway tree (see test/smoke.sh) instead of the real
# system.

set -euo pipefail

REPO="${REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
FILES="$REPO/files"

# Every file we install carries this string, so uninstall can tell ours apart
# from a config the user wrote, and never deletes the latter.
MARKER="managed by wezterm-omarchy"

# Omarchy is installed system-wide here; the user overlay lives in ~/.config.
PREFIX="${PREFIX:-/usr/share/omarchy}"
SKEL="${SKEL:-/etc/skel}"
ETC="${ETC:-/etc}"
ENVIRONMENT_D="${ENVIRONMENT_D:-/usr/lib/environment.d}"

DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"

if [[ -t 1 ]]; then
  C_OK=$'\033[32m' C_WARN=$'\033[33m' C_ERR=$'\033[31m' C_DIM=$'\033[2m' C_OFF=$'\033[0m'
else
  C_OK="" C_WARN="" C_ERR="" C_DIM="" C_OFF=""
fi

say() { printf '%s==>%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s==> warning:%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die() { printf '%s==> error:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }
note() { printf '%s    %s%s\n' "$C_DIM" "$*" "$C_OFF"; }

# Run a command, or describe it when DRY_RUN=1.
run() {
  if [[ $DRY_RUN == 1 ]]; then
    note "[dry-run] $*"
    return 0
  fi
  "$@"
}

# Run a command with root privileges unless we already are root (for writes under
# /usr/share/omarchy, /etc and /usr/lib).
run_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    run "$@"
  else
    run sudo "$@"
  fi
}

# Whether the current target needs root. parse_scope_args sets this: a local
# install only ever writes inside $HOME, so it must never reach for sudo.
NEED_ROOT=0

# Escalate only when the current scope actually needs it. Every write goes
# through this rather than run_root directly.
run_priv() {
  if [[ ${NEED_ROOT:-0} == 1 ]]; then
    run_root "$@"
  else
    run "$@"
  fi
}

# --- scope ---------------------------------------------------------------

SCOPE=""
# Set by --hook-only: install just the reload hook, leaving the config alone.
HOOK_ONLY=0

# parse_scope_args --local|--global [--hook-only]
parse_scope_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --local) SCOPE=local ;;
      --global) SCOPE=global ;;
      --hook-only) HOOK_ONLY=1 ;;
      -h | --help)
        printf 'usage: %s --local|--global [--hook-only]\n' "$(basename "$0")"
        exit 0
        ;;
      *) die "unknown argument: $arg (expected --local or --global)" ;;
    esac
  done
  [[ -n $SCOPE ]] || die "specify --local or --global"

  # A local install only writes inside $HOME, so it must never prompt for a
  # password. Anything touching /usr/share, /etc or /usr/lib needs root.
  if [[ $SCOPE == global ]]; then
    NEED_ROOT=1
  else
    NEED_ROOT=0
  fi
}

# --- who are we -----------------------------------------------------------

# AM_ROOT overrides the root check. Only the test suite sets it: the suite must
# not run as root, but the root-only branches still need exercising, and that is
# exactly the path that has surprised people.
is_root() {
  if [[ -n ${AM_ROOT:-} ]]; then
    [[ $AM_ROOT == 1 ]]
  else
    [[ ${EUID:-$(id -u)} -eq 0 ]]
  fi
}

# The account the per-user pieces should be installed for.
#
# Under `sudo make ...` the environment is root's, so $HOME is /root and the
# per-user stage would scatter hooks and xdg-terminals.list into root's home
# while leaving the actual account alone. SUDO_USER is who really asked. Prints
# nothing when there is no such account (a genuine root login), which callers
# treat as "skip the per-user stage".
invoking_user() {
  is_root || return 0

  local user="${SUDO_USER:-}"
  [[ -n $user && $user != root ]] || return 0
  getent passwd "$user" >/dev/null 2>&1 || return 0

  printf '%s' "$user"
}

# Where per-user desktop entries are read from, mirroring the XDG rule.
user_applications_dir() {
  if [[ -n ${XDG_DATA_HOME:-} ]]; then
    printf '%s/applications' "$XDG_DATA_HOME"
  else
    printf '%s/.local/share/applications' "$HOME"
  fi
}

# --- file helpers --------------------------------------------------------

# True when the file exists and carries our marker.
is_managed() {
  [[ -f $1 ]] && grep -qF -- "$MARKER" "$1"
}

# Keep a timestamped copy before replacing something, Omarchy style. Deliberately
# not tolerant of failure: proceeding to overwrite without the backup would
# defeat the point.
backup_file() {
  local target="$1" bak
  [[ -e $target ]] || return 0
  bak="$target.bak.$(date +%s)"
  run_priv cp -a -- "$target" "$bak"
  note "backed up -> $bak"
}

# Set by install_file to 1 whenever it actually wrote something, so callers can
# skip costly follow-up work (regenerating the theme) on a no-op re-run.
INSTALL_CHANGED=0

# install_file SRC DST [MODE] [replace]
#
# Idempotent: an identical file is left alone. A file that is not ours is never
# overwritten unless FORCE=1 or the caller passes "replace" (used when we can
# positively identify the file as the old install script's one). Either way a
# backup is kept first.
install_file() {
  local src="$1" dst="$2" mode="${3:-644}" replace="${4:-}"
  [[ -f $src ]] || die "missing source file: $src"

  if [[ -e $dst ]]; then
    if cmp -s -- "$src" "$dst"; then
      note "already up to date: $dst"
      return 0
    fi
    if ! is_managed "$dst" && [[ $FORCE != 1 && $replace != replace ]]; then
      die "$dst exists and was not installed by wezterm-omarchy.
    Re-run with FORCE=1 to replace it (a backup is kept)."
    fi
    backup_file "$dst"
  fi

  run_priv install -Dm"$mode" -- "$src" "$dst"
  note "installed: $dst"
  INSTALL_CHANGED=1
}

# Remove one of our files. Anything without the marker is left alone.
remove_file() {
  local target="$1"
  [[ -e $target ]] || return 0
  if ! is_managed "$target"; then
    warn "not removing $target: it was not installed by wezterm-omarchy"
    return 0
  fi
  run_priv rm -f -- "$target"
  note "removed: $target"
}

# Remove our file, but if we displaced something earlier put it back instead.
# Used for files another program also writes, such as xdg-terminals.list.
restore_or_remove_file() {
  local target="$1" latest
  [[ -e $target ]] || return 0
  if ! is_managed "$target"; then
    warn "not touching $target: it was not installed by wezterm-omarchy"
    return 0
  fi

  latest="$(ls -1t -- "$target".bak.* 2>/dev/null | head -n1 || true)"
  if [[ -n $latest ]]; then
    run_priv cp -a -- "$latest" "$target"
    note "restored $target from $latest"
  else
    run_priv rm -f -- "$target"
    note "removed: $target"
  fi
}

# --- omarchy helpers -----------------------------------------------------

# Where Omarchy keeps per-theme generated files.
#
# Deliberately NOT ${XDG_STATE_HOME:-...}, even though that is the "correct" XDG
# form and wezterm.lua could be written either way: omarchy-theme-set and
# omarchy-theme-set-templates hardcode $HOME/.local/state/omarchy, so honouring
# XDG_STATE_HOME here would point us at a directory Omarchy never writes. The
# generated file would then always look missing (so every install would
# regenerate the theme) and uninstall would try to delete something absent.
# Follow the tool that owns the file, not the spec.
omarchy_state_dir() {
  printf '%s/.local/state/omarchy' "$HOME"
}

# Where WezTerm looks for the per-user config, mirroring its own precedence:
# $XDG_CONFIG_HOME/wezterm when that is set, else ~/.config/wezterm.
#
# Every installer and hook has to agree on this. Hardcoding ~/.config here while
# wezterm.lua preferred the XDG path would mean a local install writing a file
# that nothing ever reads, whenever XDG_CONFIG_HOME points somewhere else.
user_wezterm_dir() {
  if [[ -n ${XDG_CONFIG_HOME:-} ]]; then
    printf '%s/wezterm' "$XDG_CONFIG_HOME"
  else
    printf '%s/.config/wezterm' "$HOME"
  fi
}

# Where Omarchy writes generated per-theme files. This is the path the old
# install script got wrong -- it read ~/.config/omarchy/current/... instead.
generated_theme_file() {
  printf '%s/current/theme/wezterm.lua' "$(omarchy_state_dir)"
}

# Re-run omarchy-theme-set for the current theme so the WezTerm colours are
# generated immediately rather than at the next theme change.
regenerate_theme() {
  local name_file name
  name_file="$(omarchy_state_dir)/current/theme.name"

  if [[ ! -f $name_file ]]; then
    warn "no Omarchy theme recorded at $name_file; skipping regeneration"
    warn "run 'omarchy theme set <name>' to generate the WezTerm colours"
    return 0
  fi

  name="$(<"$name_file")"
  if ! command -v omarchy-theme-set >/dev/null 2>&1; then
    warn "omarchy-theme-set not found; run it yourself to generate the theme file"
    return 0
  fi

  say "regenerating theme '$name' so WezTerm picks up the colours now"

  # omarchy-theme-set resolves the theme directory from $OMARCHY_PATH, and
  # omarchy-theme-set-templates does the same for its templates. We cannot rely
  # on inheriting it: sudo resets the environment, so a run under sudo -- or the
  # per-user stage it spawns with `sudo -u` -- would look in /themes, find
  # nothing, and report "Theme '<name>' does not exist" for whatever theme
  # happens to be current. Pass it explicitly.
  #
  # OMARCHY_THEME_SKIP_BACKGROUND: a normal theme-set rotates to the next
  # wallpaper, and that would be a surprising side effect of installing a
  # terminal config. This flag regenerates the theme files without moving it.
  run env "OMARCHY_PATH=${OMARCHY_PATH:-$PREFIX}" OMARCHY_THEME_SKIP_BACKGROUND=1 \
    omarchy-theme-set "$name"
  [[ $DRY_RUN == 1 ]] || note "generated: $(generated_theme_file)"
}

# Generate the colours only when something changed, or when they are missing.
# `omarchy-theme-set` re-runs every post-theme hook it has (restarting terminals,
# reloading Hyprctl, retinting btop, ...), so a re-run that installed nothing new
# should not do all of that again.
regenerate_theme_if_needed() {
  local changed="${1:-1}"

  if [[ $changed == 1 || ! -f $(generated_theme_file) ]]; then
    regenerate_theme
  else
    note "theme already generated and nothing changed; not regenerating"
  fi
}

# Write a starter config, for when there is none at all. Never replaces an
# existing one -- that is the whole point of the module scheme.
create_minimal_config() { # $1 = config path
  local dst="$1" dir tmp
  dir="$(dirname -- "$dst")"
  tmp="$(mktemp)"

  cat >"$tmp" <<'EOF'
-- managed by wezterm-omarchy
-- Your WezTerm configuration.
--
-- This file is yours. The theme is applied by the two lines below, which the
-- installer put here; everything after them is yours to edit and will override
-- the theme. Deleting those lines simply means WezTerm stops following the
-- theme -- nothing breaks.
local wezterm = require("wezterm")

local config = wezterm.config_builder()

return config
EOF

  run_priv mkdir -p -- "$dir"
  run_priv install -Dm644 -- "$tmp" "$dst"
  rm -f -- "$tmp"
  note "created a starter config at $dst"
}

# Point a user's config at the theme module, by wrapping its return.
#
# Lua requires `return` to be the last statement in a block, so this cannot be
# appended to the end of the file -- anything after the return is a syntax error.
# The generated line goes immediately before it instead. Their settings are left
# exactly as they were; only that one line is added, and uninstall takes it back
# out byte for byte.
ensure_theme_loaded() { # $1 = config, $2 = theme module
  local config="$1" module="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found, so $config was not pointed at the theme"
    warn "add this line yourself, just before its 'return':"
    warn "    return dofile(\"$module\")(config)"
    return 0
  fi

  if ! run python3 "$REPO/scripts/insert-theme-load.py" "$config" "$module"; then
    # The config exists but has no config object to insert after -- a shape this
    # will not guess at. The theme module is installed either way, so the target
    # carries on and leaves the user a clear instruction rather than dying
    # partway through installing something else.
    warn "$config was left alone: it does not create a config object"
    warn "add this yourself, wherever it suits you:"
    warn "    dofile(\"$module\")(config)"
  fi
}

# The theme itself, plus the line that loads it.
#
# The theme lives in its own module so that a user's wezterm.lua is never
# replaced: it keeps its settings and gains one line. Every feature target that
# depends on the theme calls this, so whichever one you run leaves the theme
# wired up.
install_theme_module() { # $1 = path to the config that should load it
  local config="$1" module
  module="$(dirname -- "$config")/wezterm-theme.lua"

  install_file "$FILES/wezterm-theme.lua" "$module"

  if [[ ! -e $config ]]; then
    create_minimal_config "$config"
  fi

  ensure_theme_loaded "$config" "$module"
}

# System-wide: the entry point, plus the theme module beside it.
#
# Nothing is edited here. A system-wide install does not touch anyone's own
# config -- the entry point is ours and is what WezTerm loads instead, so there
# is no line to insert. The module has to sit beside it because the entry point
# loads it by path.
install_global_theme() {
  local module="$ETC/wezterm/wezterm-theme.lua" tmp_dir tmp

  install_file "$FILES/wezterm-theme.lua" "$module"

  # The entry point names the module by absolute path, substituted here: with
  # `--config-file` pointing elsewhere, resolving it from wezterm.config_file
  # would look in the wrong directory.
  tmp_dir="$(mktemp -d)"
  tmp="$tmp_dir/wezterm.lua"
  sed "s|@@THEME_MODULE@@|$module|" "$FILES/wezterm-global.lua" >"$tmp"
  install_file "$tmp" "$ETC/wezterm/wezterm.lua"
  rm -rf -- "$tmp_dir"
}

# --- leftovers from the old gist installer -------------------------------

# The widely copied install script wrote these. Nothing reads them: the theme
# template in particular landed in a directory omarchy-theme-set-templates never
# looks at, which is why that script appears to work but never themes WezTerm.
gist_leftovers() {
  printf '%s\n' \
    "$HOME/.local/share/omarchy/default/themed/wezterm.lua.tpl" \
    "$HOME/.local/share/omarchy/default/wezterm/screensaver.lua" \
    "$HOME/.local/share/omarchy/config/wezterm/wezterm.lua"
}

detect_gist_leftovers() {
  local entry found=0
  while IFS= read -r entry; do
    [[ -e $entry ]] || continue
    found=1
    break
  done < <(gist_leftovers)
  ((found)) || return 0

  say "found leftovers from the old install script"
  while IFS= read -r entry; do
    [[ -e $entry ]] || continue
    if [[ ${UNINSTALL_GIST_LEFTOVERS:-0} == 1 ]]; then
      run rm -f -- "$entry"
      note "removed: $entry"
    else
      note "unused: $entry"
    fi
  done < <(gist_leftovers)

  if [[ ${UNINSTALL_GIST_LEFTOVERS:-0} != 1 ]]; then
    note "these are inert; re-run with UNINSTALL_GIST_LEFTOVERS=1 to delete them"
  fi
}

# --- patch helpers -------------------------------------------------------

# Keep one pristine copy of a system script before we patch it, so uninstall can
# restore the original exactly rather than trying to reverse the edits.
#
# Overwrites any existing copy on purpose. Callers only reach here after checking
# the target is not already patched, so the current file IS the pristine one --
# and if an Omarchy update replaced the script since last time, the stale copy
# would otherwise be restored over the new version at uninstall.
save_original() {
  local target="$1" orig="$1.wezterm-omarchy.orig"
  [[ -e $target ]] || return 0
  run_priv cp -a -- "$target" "$orig"
}

restore_original() {
  local target="$1" orig="$1.wezterm-omarchy.orig"
  [[ -e $orig ]] || return 1
  run_priv cp -a -- "$orig" "$target"
  run_priv rm -f -- "$orig"
  note "restored original: $target"
}

# Apply TEMP -> TARGET, refusing to install a file that fails bash -n.
install_patched_script() {
  local tmp="$1" target="$2"

  if ! bash -n "$tmp" 2>/dev/null; then
    bash -n "$tmp" || true
    die "patched script failed 'bash -n', refusing to install: $target"
  fi

  run_priv install -m755 -- "$tmp" "$target"
  note "patched: $target"
}
