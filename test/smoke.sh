#!/bin/bash
# Verify that WezTerm is actually being themed.
#
# Checks the parts that were broken in the old install script, so this fails
# loudly if the theme file is not where it should be, is not valid, or is not
# reaching the config.
#
# usage: test/smoke.sh

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/common.sh
source "$REPO/scripts/common.sh"

failures=0
pass() { printf '%s  ok  %s %s\n' "$C_OK" "$C_OFF" "$*"; }
fail() {
  printf '%s FAIL %s %s\n' "$C_ERR" "$C_OFF" "$*"
  failures=$((failures + 1))
}

# --- find what is installed -------------------------------------------------

theme_file="$(generated_theme_file)"

if [[ -f $HOME/.config/wezterm/wezterm.lua ]]; then
  config_file="$HOME/.config/wezterm/wezterm.lua"
elif [[ -f $ETC/wezterm/wezterm.lua ]]; then
  config_file="$ETC/wezterm/wezterm.lua"
else
  fail "no WezTerm config found; run 'make install' first"
  exit 1
fi

say "checking $config_file"
note "theme file: $theme_file"

# --- the generated theme file ----------------------------------------------

if [[ ! -f $theme_file ]]; then
  warn "theme file missing; regenerating"
  regenerate_theme
fi

if [[ -f $theme_file ]]; then
  pass "theme file exists"

  if grep -qE '^ *background *= *"#[0-9A-Fa-f]{6}"' "$theme_file"; then
    pass "theme file defines a background colour"
  else
    fail "theme file has no usable background colour"
  fi

  # A leftover placeholder means a template key Omarchy does not resolve, which
  # would leave a literal token where a colour belongs. Comments are skipped --
  # the generated file carries the template's header comment through.
  if grep -v '^[[:space:]]*--' "$theme_file" | grep -q '{{'; then
    fail "theme file still contains unsubstituted placeholders"
    grep -v '^[[:space:]]*--' "$theme_file" | grep -n '{{' | head -5 | sed 's/^/       /'
  else
    pass "theme file has no leftover placeholders"
  fi
else
  fail "theme file was not generated at $theme_file"
fi

# --- the config actually loads and picks the colours up --------------------

if ! command -v wezterm >/dev/null 2>&1; then
  warn "wezterm not on PATH; skipping load checks"
else
  probe_dir="$(mktemp -d)"
  cat >"$probe_dir/probe.lua" <<'LUA'
local wezterm = require("wezterm")
local chunk = loadfile(os.getenv("SMOKE_CONFIG"))
if not chunk then
  wezterm.log_error("SMOKE status=loadfile-failed")
  return {}
end
local ok, cfg = pcall(chunk)
if not ok then
  wezterm.log_error("SMOKE status=eval-failed " .. tostring(cfg))
  return {}
end
local colors = cfg.colors
wezterm.log_error("SMOKE status=ok background=" .. tostring(colors and colors.background)
  .. " ansi1=" .. tostring(colors and colors.ansi and colors.ansi[1])
  .. " font_size=" .. tostring(cfg.font_size))
return {}
LUA

  out="$(SMOKE_CONFIG="$config_file" timeout 20 \
    wezterm --config-file "$probe_dir/probe.lua" ls-fonts 2>&1 || true)"
  rm -rf -- "$probe_dir"

  status="$(sed -n 's/.*SMOKE status=\([^ ]*\).*/\1/p' <<<"$out" | head -n1)"
  case "$status" in
    ok)
      pass "config loads and evaluates"
      bg="$(sed -n 's/.*background=\([^ ]*\).*/\1/p' <<<"$out" | head -n1)"
      if [[ $bg =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        pass "Omarchy colours reached the config (background $bg)"
      else
        fail "config loaded but no theme colours (background '$bg') -- is the template installed?"
      fi
      ;;
    loadfile-failed) fail "config could not be loaded at $config_file" ;;
    eval-failed)
      fail "config raised an error"
      sed -n 's/.*SMOKE status=eval-failed //p' <<<"$out" | head -3 | sed 's/^/       /'
      ;;
    *)
      fail "config did not evaluate"
      tail -5 <<<"$out" | sed 's/^/       /'
      ;;
  esac

  if grep -q 'wezterm-omarchy: could not load theme' <<<"$out"; then
    fail "the config reported it could not find the theme file"
  else
    pass "no 'could not load theme' errors"
  fi

  # A single unrecognised key makes WezTerm reject the whole config, not just
  # that key -- a window_frame inside colors broke the entire palette, and the
  # only symptom was this error on every launch. Worth catching here rather than
  # in a window that silently loses its theme.
  if grep -qiE 'error converting|is not a valid|stack traceback' <<<"$out"; then
    fail "WezTerm rejected the config"
    grep -iE 'error converting|is not a valid|Did you mean' <<<"$out" | head -3 | sed 's/^/       /'
  else
    pass "WezTerm accepted the config, no conversion errors"
  fi

  # --- the screensaver and the default terminal have to agree -------------
  #
  # Omarchy's screensaver only runs in a hardcoded list of host terminals, in a
  # root-owned script. Making WezTerm the default without teaching that list
  # leaves the screensaver refusing to start, and the only symptom is a
  # "Screensaver only runs in ..." notification.
  if command -v xdg-terminal-exec >/dev/null 2>&1; then
    default_terminal="$(xdg-terminal-exec --print-id 2>/dev/null || true)"
    launcher="$PREFIX/bin/omarchy-launch-screensaver"

    if [[ $default_terminal != *wezterm* ]]; then
      pass "WezTerm is not the default terminal, so the screensaver is unaffected"
    elif [[ ! -f $launcher ]]; then
      skip "no omarchy-launch-screensaver found; cannot check"
    elif grep -qF '*wezterm*' "$launcher"; then
      pass "the screensaver accepts WezTerm"
    else
      warn "WezTerm is the default terminal but Omarchy's screensaver does not accept it"
      note "the screensaver will refuse to start. Fix it with:"
      note "    sudo make install-screensaver-global"
    fi
  fi

  # --- is the theme wired up, and current? --------------------------------
  #
  # The theme now lives in its own module and the user's config loads it, so the
  # things to check are that the module matches the repo and that the config
  # still carries the line that loads it. Editing files/wezterm-theme.lua and
  # running a target that does not install it would otherwise fail silently.
  module="$(dirname -- "$config_file")/wezterm-theme.lua"
  if [[ -f $module ]]; then
    if cmp -s "$REPO/files/wezterm-theme.lua" "$module"; then
      pass "theme module matches files/wezterm-theme.lua"
    else
      warn "the installed theme module differs from $REPO/files/wezterm-theme.lua"
      note "install it with: make install-theme-local"
    fi
  else
    fail "no theme module at $module -- the theme is not wired up"
  fi

  if grep -q 'wezterm-omarchy: load the Omarchy theme' "$config_file"; then
    pass "your config loads the theme"
  else
    warn "your config does not load the theme"
    note "add it with: make install-theme-local"
  fi

  # --- the recursion guard ----------------------------------------------
  #
  # With a system-wide install the config is both the entry point and a valid
  # per-user config, so a symlinked copy must not make it load itself forever.
  # A string path comparison does not catch that; the guard flag must.
  guard_dir="$(mktemp -d)"
  mkdir -p "$guard_dir/home/.config/wezterm"
  ln -sf "$config_file" "$guard_dir/home/.config/wezterm/wezterm.lua"

  if timeout 20 env -u XDG_CONFIG_HOME HOME="$guard_dir/home" \
    wezterm --config-file "$config_file" ls-fonts >/dev/null 2>&1; then
    pass "config does not recurse when it is also the user config"
  else
    fail "config failed or hung when it is also the user config (recursion guard)"
  fi
  rm -rf -- "$guard_dir"
fi

# --- summary ---------------------------------------------------------------

printf '\n'
if ((failures == 0)); then
  printf '%sall checks passed%s\n\n' "$C_OK" "$C_OFF"
else
  printf '%s%d check(s) failed%s\n\n' "$C_ERR" "$failures" "$C_OFF"
  exit 1
fi
