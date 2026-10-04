#!/bin/bash
# Optional: ignore brief focus loss at screensaver startup.
#
# The old install script patched this in. It exists because omarchy-screensaver
# exits the moment its window is not the focused one:
#
#     if read -n1 -t 1 || ! screensaver_in_focus; then exit_screensaver; fi
#
# and with one screensaver per monitor, focus moves to start the next monitor's
# window. WezTerm starts slower than Alacritty, so on a slow start the
# already-running instance can see focus move before the next window has mapped
# and quit straight away.
#
# This Omarchy version already fixes that upstream: omarchy-launch-screensaver has
# wait_for_screensaver_window, which blocks until each monitor's window has
# actually mapped before moving focus on. So the patch is normally unnecessary,
# and applying it costs you the focus check for the first few seconds (a click
# away is ignored during that window). It is here for anyone who still sees
# screensaver windows vanishing, and refuses to apply unless asked twice.
#
# usage: install-screensaver-grace.sh --global [FORCE_GRACE=1]

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"
[[ $SCOPE == global ]] || die "this patches $PREFIX/bin/omarchy-screensaver; use --global"

runner="$PREFIX/bin/omarchy-screensaver"
launcher="$PREFIX/bin/omarchy-launch-screensaver"

[[ -f $runner ]] || die "not found: $runner (is Omarchy installed?)"

# Not -F: the ^ is an anchor here, and -F would make it a literal caret that
# never matches, so this guard would never fire on a second run.
if grep -q '^GRACE_SECONDS=' "$runner"; then
  say "the grace patch is already applied"
  exit 0
fi

if ! grep -qF 'read -n1 -t 1 || ! screensaver_in_focus' "$runner"; then
  warn "omarchy-screensaver no longer matches this pattern -- its shape has changed."
  warn "There is nothing to patch; if screensaver windows are still vanishing,"
  warn "fix it upstream instead."
  exit 0
fi

if grep -qF 'wait_for_screensaver_window' "$launcher" && [[ ${FORCE_GRACE:-0} != 1 ]]; then
  say "this Omarchy already handles the multi-monitor focus race"
  note "omarchy-launch-screensaver waits for each monitor's window to map before"
  note "moving focus, which is what this patch worked around."
  note ""
  note "Nothing was changed. If screensaver windows still vanish, apply it with:"
  note "    FORCE_GRACE=1 make install-screensaver-grace-global"
  exit 0
fi

say "applying the screensaver focus grace patch"

tmp_dir="$(mktemp -d)"
tmp="$tmp_dir/omarchy-screensaver"

awk '
  # give the script a grace period to measure against
  /^# omarchy:summary=/ {
    print
    print ""
    print "# Ignore focus loss briefly while one screensaver window is started per monitor."
    print "GRACE_SECONDS=4"
    next
  }
  /^tty=\$\(tty 2>\/dev\/null\)$/ {
    print
    print "start_seconds=$SECONDS"
    next
  }
  # stop treating a transient focus loss as the user walking away
  /^[[:space:]]*if read -n1 -t 1 \|\| ! screensaver_in_focus; then[[:space:]]*$/ {
    print "    if read -n1 -t 1; then"
    print "      exit_screensaver"
    print "    elif (( SECONDS - start_seconds >= GRACE_SECONDS )) && ! screensaver_in_focus; then"
    print "      exit_screensaver"
    print "    fi"
    skip_until_fi = 1
    next
  }
  skip_until_fi {
    if ($0 ~ /^[[:space:]]*fi[[:space:]]*$/) { skip_until_fi = 0 }
    next
  }
  { print }
' "$runner" >"$tmp"

grep -qF 'GRACE_SECONDS=4' "$tmp" || die "patch did not apply; omarchy-screensaver shape changed"
grep -qF 'start_seconds=$SECONDS' "$tmp" || die "patch did not apply; tty line shape changed"

save_original "$runner"
install_patched_script "$tmp" "$runner"
rm -rf -- "$tmp_dir"

note "focus loss is now ignored for ${GRACE_SECONDS:-4}s after the screensaver starts"
warn "owned by the Omarchy package; an update may revert this"
