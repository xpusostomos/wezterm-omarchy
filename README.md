# wezterm-omarchy

Make [WezTerm](https://wezterm.org) follow the active
[Omarchy](https://github.com/basecamp/omarchy) colour scheme, and change colour
live when you switch theme.

```console
$ make install
```

It asks whether to install for your account only or for the whole machine.

## Quick start

```console
make install          # asks: this user, or the whole system
make check            # verify the live install: colours reaching WezTerm
make test             # test the installers in a sandbox (no root, nothing touched)
make help             # list every target
```

`make check` looks at your actual install. `make test` instead exercises the
installers themselves — install, re-install, and uninstall for both scopes, in a
throwaway tree with a stub `sudo`, asserting that re-running changes nothing,
that uninstall restores what was there, and that a system-wide install leaves
your own config alone. It never reads or writes outside a temp directory.

Requirements: WezTerm and Omarchy already installed.

### Local or global?

You choose this with the target name — `make install-all-local` or
`make install-all-global`. (`make install` asks, and `MODE=local|global` skips
the question.)

| | local (recommended) | global |
|---|---|---|
| Root needed | no | yes |
| Scope | your account | every account |
| Survives Omarchy updates | yes | **no** — see below |
| Theme template | `~/.config/omarchy/themed/` | `$PREFIX/default/themed/` |
| Reload hook | `~/.config/omarchy/hooks/theme-set.d/` | (per-user only) |
| Config entry point | `~/.config/wezterm/wezterm.lua` | `/etc/wezterm/wezterm.lua` via `WEZTERM_CONFIG_FILE` |

**Prefer local.** It needs no root and lives entirely in your home, so Omarchy
updates cannot clobber it. Global works, but it writes into `/usr/share/omarchy`,
which is owned by the Omarchy package — an update may revert those files, in which
case re-run `make install-all-global`.

`install-all-global` also applies the per-user pieces for the account running it
(a system install that leaves you unthemed would look broken). Use
`GLOBAL_SKIP_USER=1` to skip that.

### What it does to your config

**It never edits your config in place.** There is no patching, no line injection,
and no rewriting of settings you already have. Everything is whole-file: it either
writes its own file or it leaves yours alone. That decides what "your config" does
differently in the two modes:

| | local install | global install |
|---|---|---|
| `~/.config/wezterm/wezterm.lua` | **replaced** by ours | **left untouched** |
| Your settings | kept only in a `.bak` copy | still apply — merged on top, and win |
| How the theme reaches WezTerm | our config *is* your config | `/etc/wezterm/wezterm.lua` loads your config and merges it |

So **local replaces, global augments.**

**Local** writes its own `~/.config/wezterm/wezterm.lua`. Because that would
otherwise silently destroy a config you wrote, it refuses and tells you to re-run
with `FORCE=1`; with that, your original is copied to `wezterm.lua.bak.<timestamp>`
first. The one exception is the old install script's config, which is recognised
by the bad theme path it reads and migrated automatically — backing it up and
replacing it without needing `FORCE`.

**Global** writes `/etc/wezterm/wezterm.lua` and points `WEZTERM_CONFIG_FILE` at
it. That file themes WezTerm and then loads your own
`~/.config/wezterm/wezterm.lua` if you have one, letting your settings win. So a
system-wide install themes every account, including ones that already had a
config, without touching any of them. `install-all-global` follows the same rule
for the account running it — it installs only the hooks and
`xdg-terminals.list`, never the config.

If you want WezTerm themed *and* keep full control of the config, use the global
install with `GLOBAL_SKIP_USER=1`; if you don't mind our config becoming yours,
the local install is simpler and needs no root.

## Targets

Each feature is independent, so you can install only what you want:

```console
make install-theme-local        # theme colours + live reload
make install-font-local         # follow `omarchy font set`
make install-terminal-local     # make WezTerm the default terminal
make install-screensaver-global # let Omarchy's screensaver run in WezTerm
make install-menus-global       # teach Omarchy's terminal pickers about WezTerm
make install-tabs-local         # hide the tab bar (see below)
make install-all-local          # all of the above, for this user
make install-all-global         # all of the above, system-wide

make uninstall-local
make uninstall-global
```

### The tab bar

**Installing the theme does not touch your tab bar.** That is deliberate:
`install-all-*` does not include it either, and it only changes when you ask for
it by name.

```console
make install-tabs-local        # hide the tab bar
make uninstall-tabs-local      # bring it back
```

Hiding it is arguably the more Omarchy look — Omarchy's own terminals have no tab
bar — but it *takes a feature away* rather than restyling one, so it lives in its
own file (`omarchy-tabs-hidden.lua`) with its own target, and a theme install
never quietly switches it off.

If you would rather `install-all` matched Omarchy's look completely, add
`install-tabs-local` to `install-all.sh`, or just run it once after.

Useful variables: `MODE=local|global` (skip the prompt), `DRY_RUN=1`,
`FORCE=1`, `PREFIX=…` (for testing against a throwaway tree).

The Makefile is a thin front end; each target calls a script in `scripts/`. The
`--local` / `--global` flags in a script's usage line are that lower level —
`make install-theme-local` is exactly `scripts/install-theme.sh --local`. Call a
script directly if you would rather skip make.

## How it works

**Colours.** Omarchy regenerates a file per theme from a template. Installing
`wezterm.lua.tpl` into a directory Omarchy actually reads makes it generate
`~/.local/state/omarchy/current/theme/wezterm.lua`, a small Lua table of colours,
exactly as it does for Alacritty, Kitty and Ghostty.

**Live reload.** `wezterm.lua` loads that generated file and puts it on WezTerm's
config reload watch list (`wezterm.add_to_config_reload_watch_list`). Omarchy
rewrites the file on every `omarchy theme set`, so open windows re-colour with no
restart and no patched scripts. A hook in `theme-set.d/` touches the config as a
fallback for WezTerm builds without that function.

**Font.** The font is resolved at load time from fontconfig (`fc-match monospace`),
which is where `omarchy font set` records its choice — so WezTerm follows
`omarchy font set` rather than hardcoding a family. A hook in `font-set.d/`
prompts a reload.

### The system-wide config, and logging back in

**WezTerm has no global config file by default.** It looks only at
`$WEZTERM_CONFIG_FILE`, then `$XDG_CONFIG_HOME/wezterm/wezterm.lua`, then
`~/.config/wezterm/wezterm.lua`, then `~/.wezterm.lua`. Nothing system-wide is
consulted, which is why a global install has to arrange it:

1. `install-global-config` writes `/etc/wezterm/wezterm.lua`.
2. It sets `WEZTERM_CONFIG_FILE=/etc/wezterm/wezterm.lua` in
   `/usr/lib/environment.d/99-wezterm-omarchy.conf`.
3. That config then loads *your* own config, if you have one, and lets your
   settings win. So a system-wide install themes every account without taking
   away anyone's config.

   Your config is looked for at `$XDG_CONFIG_HOME/wezterm/wezterm.lua` when
   `XDG_CONFIG_HOME` is set, and at `~/.config/wezterm/wezterm.lua` otherwise —
   the same order WezTerm itself uses, including falling back to `~/.config` when
   the XDG path does not exist. The installer writes to whichever of the two
   applies, so a local install and the loader always agree.

Step 2 is `/usr/lib/environment.d/`, **not `/etc/profile` or `/etc/profile.d`**.
Those are read by login shells, and a WezTerm started from a Hyprland keybind
never passes through one — it is launched by `omarchy-launch-terminal` through
`uwsm-app` into the systemd user session, and `environment.d` is what that reads.
A variable in `profile.d` would work when you run `wezterm` by hand from another
terminal and quietly do nothing from the keybind, which is the worst way to find
out. (`/etc/profile.d/wezterm.sh` does exist on this machine, but it is the
WezTerm package's shell integration — OSC sequences for prompt marking — and has
nothing to do with loading config.)

**It will not take effect until you log out and back in.** The systemd user
session reads `environment.d` once, when the user manager starts; editing it does
not update a session already running, so the variable is simply absent until the
next login. Restart WezTerm after that as well.

There is no way around the re-login for a keybind launch, because Hyprland itself
inherits its environment when *it* starts, and a keybind-launched WezTerm inherits
Hyprland's — so nothing you change mid-session reaches it. (`systemctl --user
set-environment` updates the user manager, but Hyprland is not re-reading it.)

To try the global config out before logging out, start WezTerm with the variable
set directly. That is the only path that will pick it up:

```console
WEZTERM_CONFIG_FILE=/etc/wezterm/wezterm.lua wezterm
```

One consequence worth knowing: if `WEZTERM_CONFIG_FILE` is set but the file it
names is missing, WezTerm errors and loads *no* config at all rather than falling
back to your `~/.config` one. The variable and the file must stay together, which
is why `uninstall-global` removes the environment file before the config.

## The screensaver

Omarchy's "screensaver" is a fullscreen terminal running `omarchy-screensaver`,
which animates Omarchy's branding with `ttfx` on a black background. The terminal
is only the host for the animation.

`omarchy-launch-screensaver` hardcodes a list of host terminals and otherwise
refuses, so WezTerm has to be added to it. That script is under
`/usr/share/omarchy/bin`, which takes precedence over `~/.local/bin`, so there is
no per-user override — this is the one feature that requires root, and the reason
there is no local screensaver target.

The old script also patched in a `GRACE_SECONDS` workaround for a multi-monitor
focus race. That is deliberately **not** applied here: this version of Omarchy
already fixes it upstream in `wait_for_screensaver_window`. It is available as
`make install-screensaver-grace-global` if you still see screensaver windows
vanishing, and that target will tell you when it thinks the patch is unnecessary.

## Uninstalling

```console
make uninstall-local
make uninstall-global
```

Only files carrying the `managed by wezterm-omarchy` marker are removed, so a
config you wrote yourself is never deleted. Files replaced during install keep a
`.bak.<timestamp>` copy alongside them; patched Omarchy scripts are restored from
the pristine copy saved at install time.

## Troubleshooting

**WezTerm has its built-in colours.** Run `make check`. It reports whether the
generated theme file exists, whether it is fully substituted, and whether the
colours reach the config. The usual cause is the template not being in a
directory Omarchy reads — see the four bugs above.

**Colours do not update when I switch theme.** Run
`wezterm --config-file ~/.config/wezterm/wezterm.lua` and press `CTRL+SHIFT+R` to
force a reload. If that fixes it, the watch list is not working on your WezTerm
build; the `theme-set.d` hook should cover it.

**Global install had no effect.** `WEZTERM_CONFIG_FILE` comes from the systemd
user session, so log out and back in, then restart WezTerm.

**An Omarchy update reverted things.** Expected for anything installed globally,
since those paths are package-owned. Re-run the target.
