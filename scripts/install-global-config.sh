#!/bin/bash
# Install a system-wide WezTerm config, and the environment file that points
# WezTerm at it.
#
# WezTerm has no built-in system-wide config path, but it does honour
# $WEZTERM_CONFIG_FILE. So the global install ships an entry-point config and one
# environment file naming it. The entry point then loads each user's own
# ~/.config/wezterm/wezterm.lua if they have one and lets it win, so a global
# install themes everyone without taking away their own config.
#
# usage: install-global-config.sh --global

set -euo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

parse_scope_args "$@"

if [[ $SCOPE != global ]]; then
  die "the system-wide config only exists for --global; --local uses WezTerm's normal ~/.config path"
fi

config_dst="$ETC/wezterm/wezterm.lua"
env_dst="$ENVIRONMENT_D/99-wezterm-omarchy.conf"

say "installing the system-wide WezTerm config"

# Order matters, and this is not cosmetic: if WEZTERM_CONFIG_FILE is set but the
# file it names is missing, WezTerm errors and loads *no* config at all rather
# than falling back. So the config is installed before anything points at it.
# uninstall-global removes them in the reverse order for the same reason.
install_file "$FILES/wezterm.lua" "$config_dst"

# Generated rather than copied so the real path is baked in even when ETC is
# overridden for testing.
tmp_dir="$(mktemp -d)"
tmp_env="$tmp_dir/wezterm.environment.conf"
sed "s|^WEZTERM_CONFIG_FILE=.*|WEZTERM_CONFIG_FILE=$config_dst|" \
  "$FILES/wezterm.environment.conf" >"$tmp_env"
install_file "$tmp_env" "$env_dst"
rm -rf -- "$tmp_dir"

say "system-wide WezTerm config installed"
note "reaches WezTerm through the systemd user session, so a keybind launch sees it"
warn "a running WezTerm needs a restart, and existing sessions need a re-login,"
warn "for the environment variable to take effect"
