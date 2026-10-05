#!/bin/bash
# Round-trip and idempotency tests for the installers.
#
# Everything happens in a throwaway tree: HOME, PREFIX, SKEL, ETC and
# ENVIRONMENT_D are all redirected, and a stub `sudo` stands in so the
# system-wide path can be exercised without root. Nothing outside the temp
# directory is read or written, so this is safe to run anywhere.
#
# These are the checks that caught the real bugs during development, kept so they
# stay caught: re-running must be a no-op, uninstall must restore what was there,
# installing globally must not touch the account's own config, and re-patching an
# Omarchy script must not double-apply.
#
# usage: test/install-matrix.sh

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/home" "$SB/prefix/bin" "$SB/etc" "$SB/envd" "$SB/skel" "$SB/shim"
cat >"$SB/shim/sudo" <<'SHIM'
#!/bin/bash
# Stand-in for sudo, used only by this test: runs the command directly, dropping
# -u USER and -H so everything stays inside the throwaway tree.
args=()
while (($#)); do
  case "$1" in
    -u) shift 2 ;;
    -H) shift ;;
    --) shift; args+=("$@"); break ;;
    *) args+=("$1"); shift ;;
  esac
done
[[ ${#args[@]} -gt 0 ]] && exec "${args[@]}"
exit 0
SHIM
chmod +x "$SB/shim/sudo"

# Real Omarchy scripts to patch, when Omarchy is actually installed. Without them
# the script-patching targets are skipped rather than failed.
#
# Prefer the .wezterm-omarchy.orig copy, which holds the pristine upstream
# content. The live script may itself be patched -- it is, if you have already
# run the global install -- and copying that would leave nothing to patch, so
# every patch assertion below would pass without testing anything.
patched_scripts=(omarchy-launch-screensaver omarchy-default-terminal omarchy-install-terminal omarchy-screensaver)
pristine="$SB/pristine"
mkdir -p "$pristine"
have_omarchy=0
for s in "${patched_scripts[@]}"; do
  src=""
  if [[ -f /usr/share/omarchy/bin/$s.wezterm-omarchy.orig ]]; then
    src="/usr/share/omarchy/bin/$s.wezterm-omarchy.orig"
  elif [[ -f /usr/share/omarchy/bin/$s ]]; then
    src="/usr/share/omarchy/bin/$s"
  fi
  [[ -n $src ]] || continue
  cp "$src" "$pristine/$s"
  cp "$src" "$SB/prefix/bin/$s"
  have_omarchy=1
done

if [[ -t 1 ]]; then GREEN=$'\033[32m' RED=$'\033[31m' BOLD=$'\033[1m' OFF=$'\033[0m'; else GREEN="" RED="" BOLD="" OFF=""; fi

failures=0
pass() { printf '  %sok%s    %s\n' "$GREEN" "$OFF" "$*"; }
fail() {
  printf '  %sFAIL%s  %s\n' "$RED" "$OFF" "$*"
  failures=$((failures + 1))
}
skip() { printf '  skip  %s\n' "$*"; }
section() { printf '\n%s%s%s\n' "$BOLD" "$*" "$OFF"; }

# Run one of our scripts against the throwaway tree.
run() {
  # Every XDG_* that a path helper consults has to be cleared, or the caller's
  # environment can point a write back into the real home: XDG_DATA_HOME set in
  # a session is exactly how this test once wrote a desktop entry into the actual
  # ~/.local/share/applications.
  env -u XDG_STATE_HOME -u XDG_CONFIG_HOME -u XDG_DATA_HOME \
    PATH="$SB/shim:$PATH" HOME="$SB/home" REPO="$REPO" \
    PREFIX="$SB/prefix" SKEL="$SB/skel" ETC="$SB/etc" ENVIRONMENT_D="$SB/envd" \
    bash "$REPO/scripts/$1" "${@:2}"
}

snapshot() {
  find "$SB" -path "$SB/shim" -prune -o -type f -print0 2>/dev/null \
    | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -c1-16
}
count_baks() { find "$SB" -name '*.bak.*' 2>/dev/null | wc -l; }

# Guard against the sandbox leaking into the real account. The installers all run
# with a redirected HOME, but an inherited XDG_* variable can point a path back
# at the real home -- which is how this suite once wrote a desktop entry into the
# actual ~/.local/share/applications. Compare hashes of the files we could touch
# before and after, and shout if any changed.
REAL_HOME="$HOME"
real_files=(
  "$REAL_HOME/.config/wezterm/wezterm.lua"
  "$REAL_HOME/.config/wezterm/omarchy-tabs-hidden.lua"
  "$REAL_HOME/.config/xdg-terminals.list"
  "$REAL_HOME/.local/share/applications/org.wezfurlong.wezterm.desktop"
  "$REAL_HOME/.config/omarchy/hooks/theme-set.d/wezterm"
)
real_state() {
  local p
  for p in "${real_files[@]}"; do
    if [[ -e $p ]]; then sha256sum "$p"; else echo "absent $p"; fi
  done | sha256sum | cut -c1-16
}
real_before="$(real_state)"

user_config="$SB/home/.config/wezterm/wezterm.lua"
write_user_config() {
  mkdir -p "$(dirname "$user_config")"
  printf 'local w=require("wezterm")\nlocal c=w.config_builder()\nc.font_size=33.0 -- MINE\nreturn c\n' \
    >"$user_config"
}
user_config_intact() { [[ -f $user_config ]] && grep -q 'MINE' "$user_config"; }

# ===========================================================================
section "local install, clean account"
# ===========================================================================

run install-all.sh --local >/dev/null 2>&1 || fail "install-all --local exited non-zero"
[[ -x $SB/home/.config/omarchy/hooks/theme-set.d/wezterm ]] \
  && pass "reload hook installed" || fail "reload hook missing"
[[ -f $SB/home/.config/omarchy/themed/wezterm.lua.tpl ]] \
  && pass "theme template installed where Omarchy reads it" \
  || fail "theme template missing (must be in ~/.config/omarchy/themed)"

baks_before=$(count_baks)
l1="$(snapshot)"
run install-all.sh --local >/dev/null 2>&1
l2="$(snapshot)"
[[ $l1 == $l2 ]] && pass "re-running is a no-op (hash $l2)" || fail "re-running changed the tree"
[[ $(count_baks) -eq $baks_before ]] \
  && pass "re-running created no backup files" \
  || fail "re-running created backups"

tab1="$(snapshot)"
run install-tabs.sh --local >/dev/null 2>&1
run install-tabs.sh --local >/dev/null 2>&1
tab2="$(snapshot)"
[[ $tab1 != "$tab2" ]] || fail "tabs target had no effect"
[[ -f $SB/home/.config/wezterm/omarchy-tabs-hidden.lua ]] \
  && pass "tab-bar add-on installed" || fail "tab-bar add-on missing"
run uninstall.sh --local >/dev/null 2>&1
[[ -e $SB/home/.config/wezterm/omarchy-tabs-hidden.lua ]] \
  && fail "tab-bar add-on not removed" || pass "tab-bar add-on removed"

# The font target has to install the config, because the font lives in it. It
# used to install only the hook, so editing wezterm.lua and running it did
# nothing whatsoever.
run install-all.sh --local >/dev/null 2>&1
printf -- '-- managed by wezterm-omarchy\nlocal w=require("wezterm")\nreturn w.config_builder() -- STALE\n' \
  >"$SB/home/.config/wezterm/wezterm.lua"
run install-font.sh --local >/dev/null 2>&1
cmp -s "$REPO/files/wezterm.lua" "$SB/home/.config/wezterm/wezterm.lua" \
  && pass "install-font-local installs wezterm.lua, not just the hook" \
  || fail "install-font-local left a stale config in place"

run install-tabs.sh --local >/dev/null 2>&1
cmp -s "$REPO/files/wezterm.lua" "$SB/home/.config/wezterm/wezterm.lua" \
  && pass "install-tabs-local installs the config too" \
  || fail "install-tabs-local left a stale config in place"

# The desktop entry is what lets xdg-terminal-exec pass --app-id through, which
# is what gives Omarchy's TUI launchers (the package installer, btop, disk
# usage) the class they are floated by. Without it they come up as tiled windows.
if command -v xdg-terminal-exec >/dev/null 2>&1; then
  entry="$SB/home/.local/share/applications/org.wezfurlong.wezterm.desktop"
  if [[ -f $entry ]] && grep -q '^X-TerminalArgAppId=' "$entry"; then
    pass "desktop entry installed with the X-TerminalArg mappings"
  else
    fail "desktop entry missing or has no AppId mapping (floating TUIs would tile)"
  fi

  cmd=$(env -u XDG_CONFIG_HOME HOME="$SB/home" XDG_DATA_HOME="$SB/home/.local/share" \
    xdg-terminal-exec --print-cmd --app-id=org.omarchy.terminal -e true 2>/dev/null | tr '\n' ' ')
  [[ $cmd == *--class=org.omarchy.terminal* ]] \
    && pass "xdg-terminal-exec passes --app-id through to WezTerm" \
    || fail "xdg-terminal-exec drops --app-id (composed: $cmd)"

  # The composed command has to actually run, not merely look right. It once
  # carried --cwd twice -- the stock `Exec=wezterm start --cwd .` plus the
  # X-TerminalArgDir mapping -- and wezterm rejects a repeated --cwd outright
  # ("cannot be used multiple times") and exits without starting, so SUPER+RETURN
  # silently did nothing.
  cwd_cmd=$(env -u XDG_CONFIG_HOME HOME="$SB/home" XDG_DATA_HOME="$SB/home/.local/share" \
    xdg-terminal-exec --print-cmd --dir=/tmp -e true 2>/dev/null | tr '\n' ' ')
  n=$(grep -o -- '--cwd' <<<"$cwd_cmd" | wc -l)
  ((n <= 1)) \
    && pass "composed command carries at most one --cwd" \
    || fail "composed command repeats --cwd, so wezterm would refuse to start: $cwd_cmd"

  grep -qE '^Exec=wezterm start$' "$entry" \
    && pass "desktop entry's Exec is bare, leaving --cwd to the mapping" \
    || fail "desktop entry's Exec sets --cwd as well as the mapping (duplicate)"
else
  skip "xdg-terminal-exec not installed; skipping desktop-entry checks"
fi

# The default-terminal SELECTOR is data, not code: omarchy-menu.jsonc holds one
# row per terminal, each gated by `omarchy-cmd-present`. Without a wezterm row it
# can never appear there however the scripts are patched -- which is exactly what
# was wrong before.
menu_file="$SB/home/.config/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $menu_file ]] && grep -q 'setup.default.terminal.wezterm' "$menu_file"; then
  pass "menu row added to Omarchy's menu extensions"
  if python3 -c 'import json,re,sys
t=re.sub(r"//.*","",open(sys.argv[1]).read())
t=re.sub(r",(\s*[}\]])",r"\1",t)
json.loads(t)' "$menu_file" 2>/dev/null; then
    pass "menu file still parses"
  else
    fail "menu file does not parse -- the menu would break"
  fi
else
  fail "no wezterm row in the menu extensions (selector would not offer it)"
fi
[[ -x $SB/home/.local/bin/wezterm-omarchy-default-terminal ]] \
  && pass "menu row's helper installed" \
  || fail "menu row helper missing -- the row's action would fail"

# ===========================================================================
section "a config we did not write"
# ===========================================================================

write_user_config
if run install-theme.sh --local >/dev/null 2>&1; then
  fail "install-theme overwrote a hand-written config without FORCE"
else
  pass "refuses to replace a hand-written config (exit non-zero)"
fi
user_config_intact && pass "that config is still intact" || fail "that config was damaged"

FORCE=1 run install-theme.sh --local >/dev/null 2>&1 || fail "FORCE=1 install failed"
grep -q 'managed by wezterm-omarchy' "$user_config" \
  && pass "FORCE=1 replaced it with ours" || fail "FORCE=1 did not install"
grep -lq 'MINE' "$SB/home/.config/wezterm/"*.bak.* 2>/dev/null \
  && pass "the original was kept as a .bak" || fail "no backup of the original"

run uninstall.sh --local >/dev/null 2>&1
user_config_intact && pass "uninstall restored the original" || fail "uninstall did not restore it"

# ===========================================================================
section "global install"
# ===========================================================================

run install-all.sh --global >/dev/null 2>&1 || fail "install-all --global exited non-zero"
[[ -f $SB/etc/wezterm/wezterm.lua ]] && pass "system-wide config written" || fail "no /etc/wezterm config"
grep -q '^WEZTERM_CONFIG_FILE=' "$SB/envd/99-wezterm-omarchy.conf" 2>/dev/null \
  && pass "WEZTERM_CONFIG_FILE set in environment.d" || fail "environment.d file missing"

user_config_intact \
  && pass "the account's own config survives a global install" \
  || fail "global install touched the account's config"

[[ -f $SB/skel/.config/omarchy/hooks/font-set.d/wezterm ]] \
  && pass "font hook seeded into the skeleton for new accounts" \
  || fail "skeleton not seeded (README says the global install does this)"
[[ -f $SB/skel/.config/xdg-terminals.list ]] \
  && pass "default-terminal seeded into the skeleton" \
  || fail "skeleton default-terminal not seeded"

g1="$(snapshot)"
run install-all.sh --global >/dev/null 2>&1
g2="$(snapshot)"
[[ $g1 == $g2 ]] && pass "re-running globally is a no-op (hash $g2)" || fail "re-running changed the tree"

if ((have_omarchy)); then
  once=1
  for s in "${patched_scripts[@]}"; do
    [[ -f $SB/prefix/bin/$s ]] || continue
    before=$(grep -c 'wezterm' "$SB/prefix/bin/$s" 2>/dev/null || :)
    ((before > 0)) || continue
    case "$s" in
    omarchy-launch-screensaver) run install-screensaver.sh --global >/dev/null 2>&1 ;;
    omarchy-default-terminal | omarchy-install-terminal) run install-menus.sh --global >/dev/null 2>&1 ;;
    *) continue ;;
    esac
    after=$(grep -c 'wezterm' "$SB/prefix/bin/$s" 2>/dev/null || :)
    [[ $before == "$after" ]] || once=0
  done
  ((once)) && pass "re-running the patchers does not double-apply" || fail "a patch was applied twice"
  [[ $(find "$SB/prefix/bin" -name '*.wezterm-omarchy.orig' | wc -l) -gt 0 ]] \
    && pass "pristine copies kept for uninstall" || fail "no .orig copies to restore from"

  # An Omarchy update replaces a patched script: the .orig must not stay stale,
  # or uninstall would restore the *old* upstream version over the new one.
  s=omarchy-default-terminal
  orig="$SB/prefix/bin/$s.wezterm-omarchy.orig"
  if [[ -f $orig ]]; then
    cp "$pristine/$s" "$SB/prefix/bin/$s"   # simulate the update
    run install-menus.sh --global >/dev/null 2>&1
    diff -q "$pristine/$s" "$orig" >/dev/null \
      && pass ".orig refreshed after an Omarchy update" || fail ".orig is stale after an update"
    run uninstall.sh --global >/dev/null 2>&1
    diff -q "$pristine/$s" "$SB/prefix/bin/$s" >/dev/null \
      && pass "uninstall restored the current upstream version" \
      || fail "uninstall restored the wrong version"
    run install-all.sh --global >/dev/null 2>&1
  fi
else
  skip "Omarchy not installed; skipping patch checks"
fi

# ===========================================================================
section "uninstall"
# ===========================================================================

run uninstall.sh --global >/dev/null 2>&1 || fail "uninstall --global exited non-zero"
[[ -e $SB/etc/wezterm/wezterm.lua ]] && fail "config left behind" || pass "system-wide config removed"
[[ -e $SB/envd/99-wezterm-omarchy.conf ]] \
  && fail "environment file left behind, so WEZTERM_CONFIG_FILE now dangles" \
  || pass "environment file removed with the config (no dangling variable)"

if ((have_omarchy)); then
  bad=0
  for s in "${patched_scripts[@]}"; do
    [[ -f "$pristine/$s" && -f $SB/prefix/bin/$s ]] || continue
    diff -q "$pristine/$s" "$SB/prefix/bin/$s" >/dev/null || bad=1
  done
  ((bad == 0)) && pass "patched scripts restored byte-identical" || fail "a patched script was not restored exactly"
fi

run uninstall.sh --local >/dev/null 2>&1 || fail "uninstall --local exited non-zero"
user_config_intact && pass "the account's own config restored" || fail "the account's config was not restored"
[[ -e $SB/home/.config/omarchy/hooks/theme-set.d/wezterm ]] \
  && fail "reload hook left behind" || pass "our per-user files removed"
grep -q 'setup.default.terminal.wezterm' "$SB/home/.config/omarchy/extensions/omarchy-menu.jsonc" 2>/dev/null \
  && fail "menu row left behind" || pass "menu row removed from the extensions"

u1="$(snapshot)"
run uninstall.sh --local >/dev/null 2>&1
run uninstall.sh --global >/dev/null 2>&1
u2="$(snapshot)"
[[ $u1 == $u2 ]] && pass "uninstalling twice is a no-op" || fail "a second uninstall changed the tree"

# ===========================================================================
section "run under sudo (the case that installs into /root by accident)"
# ===========================================================================
#
# `sudo make install` leaves HOME at /root, so the per-user stage has to recover
# the real account from SUDO_USER or it scatters hooks into root's home and
# leaves the actual account untouched. AM_ROOT makes is_root() true without the
# suite needing to be root.

root_home="$SB/roothome"
mkdir -p "$root_home"

run_as_root() { # $1 = SUDO_USER (may be empty)
  env -u XDG_STATE_HOME -u XDG_CONFIG_HOME -u XDG_DATA_HOME \
    PATH="$SB/shim:$PATH" HOME="$root_home" REPO="$REPO" AM_ROOT=1 \
    SUDO_USER="${1:-}" \
    PREFIX="$SB/prefix" SKEL="$SB/skel" ETC="$SB/etc" ENVIRONMENT_D="$SB/envd" \
    bash "$REPO/scripts/install-all.sh" --global
}

# sudo by a real account: the per-user pieces must go to that account, not root.
rm -rf "$root_home"
mkdir -p "$root_home"
run_as_root "$(id -un)" >/dev/null 2>&1
[[ -f $root_home/.config/omarchy/hooks/theme-set.d/wezterm ]] \
  && pass "under sudo, per-user pieces installed for the invoking account" \
  || fail "under sudo, the per-user pieces did not reach the invoking account"
[[ -e $root_home/.config/wezterm/wezterm.lua ]] \
  && fail "under sudo, the account's config was touched" \
  || pass "under sudo, the account's own config is still left alone"

# genuine root with no invoking account: skip, and say so, rather than litter /root.
rm -rf "$root_home"
mkdir -p "$root_home"
if run_as_root "" >"$SB/root.log" 2>&1; then
  pass "a bare root install completes"
else
  fail "a bare root install failed"
fi
[[ -e $root_home/.config/omarchy ]] \
  && fail "a bare root install wrote per-user files anyway" \
  || pass "a bare root install skipped the per-user stage"
grep -q 'no account to install the per-user pieces for' "$SB/root.log" \
  && pass "and says why" || fail "but gives no explanation"

# ===========================================================================
section "did the suite touch the real account?"
# ===========================================================================

real_after="$(real_state)"
[[ $real_before == "$real_after" ]] \
  && pass "nothing outside the throwaway tree was modified" \
  || fail "the suite modified files in $REAL_HOME -- a sandbox path leaked"

# ===========================================================================
printf '\n'
if ((failures == 0)); then
  printf '%sinstall matrix: all checks passed%s\n\n' "$GREEN" "$OFF"
else
  printf '%sinstall matrix: %d check(s) failed%s\n\n' "$RED" "$failures" "$OFF"
  exit 1
fi
