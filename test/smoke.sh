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

  # --- is the installed config actually the one in this repo? -------------
  #
  # Editing files/wezterm.lua and then running a target that does not install it
  # leaves the old config in place and nothing says so -- the edit just appears
  # to do nothing. Only checked when the installed file is ours: the file invites
  # you to edit it in place, and then a difference is expected, not a fault.
  if is_managed "$config_file"; then
    if cmp -s "$REPO/files/wezterm.lua" "$config_file"; then
      pass "installed config matches files/wezterm.lua"
    else
      warn "the installed config differs from $REPO/files/wezterm.lua"
      note "if you edited the installed copy, that is expected and fine"
      note "if you edited the repo copy, install it with: make install-theme-local"
    fi
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
