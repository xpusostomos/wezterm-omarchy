#!/usr/bin/env python3
"""Insert (or remove) the line that loads the Omarchy theme into a user's config.

The config belongs to the user. This adds exactly two lines to it:

    local config = wezterm.config_builder()
    -- wezterm-omarchy: load the Omarchy theme
    dofile("<path>")(config)          <- added
    config.font_size = 77             <- everything below still wins
    return config

Everything else -- their settings, comments, formatting and their `return` -- is
left byte for byte. There is no backup-and-replace and no FORCE: the file is
edited in place, never overwritten, and uninstall takes the two lines back out.

The line goes immediately after the config object is created, so the theme lands
first and everything the user writes below it overrides the theme.

There is deliberately no other strategy. Wrapping their returned value, e.g.
`return dofile(...)({ ... })`, would work, but it buries their settings inside the
call's argument where they cannot add or reorder anything -- the opposite of what
this is for. If there is no config object to insert after, this refuses and says
what to add, rather than mangling the file.

usage: insert-theme-load.py <config> <theme-module-path> [--remove]
"""

import re
import sys

MARK = "wezterm-omarchy"
LOAD = f"-- {MARK}: load the Omarchy theme"

# The line that creates the config object. This is the anchor: the theme load is
# inserted straight after it.
# Any variable may hold the module -- `wezterm.config_builder()` and
# `w.config_builder()` are equally common -- so the receiver is not assumed.
BUILDER = re.compile(
    r"^([ \t]*)(?:local[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*"
    r"(?:[A-Za-z_][A-Za-z0-9_]*[ \t]*\.[ \t]*)?config_builder[ \t]*\([ \t]*\)[ \t]*$",
    re.M,
)


def already(text):
    return LOAD in text


def insert(text, module):
    if already(text):
        return text, "already"

    m = BUILDER.search(text)
    if not m:
        return text, "no-config-object"

    indent, name = m.group(1), m.group(2)
    insertion = (
        f"\n{indent}{LOAD}\n"
        f"{indent}dofile({module!r})({name})"
    )

    return text[: m.end()] + insertion + text[m.end():], "inserted"


def remove(text):
    if not already(text):
        return text, "not-there"

    # The marker line and the bare call line it introduced, and nothing else.
    pattern = re.compile(
        r"^[ \t]*" + re.escape(LOAD) + r"\n"
        r"[ \t]*dofile\(.*?\)\(.*?\)[ \t]*\n",
        re.M,
    )

    if not pattern.search(text):
        return text, "unrecognised"

    return pattern.sub("", text, count=1), "removed"


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)

    path, module = sys.argv[1], sys.argv[2]
    removing = "--remove" in sys.argv[3:]

    try:
        with open(path) as fh:
            text = fh.read()
    except FileNotFoundError:
        # Nothing to wire up. The caller creates a starter config when one is
        # missing, so reaching here means somebody removed it in between.
        if removing:
            sys.exit(0)
        sys.exit(f"no config at {path}")

    text, status = remove(text) if removing else insert(text, module)

    if status == "no-config-object":
        sys.exit(
            f"refusing to edit {path}: it does not create a config object.\n"
            "The theme is loaded by adding a line just after that, so there has to\n"
            "be one. Either give it the usual shape:\n"
            "\n"
            "    local wezterm = require(\"wezterm\")\n"
            "    local config = wezterm.config_builder()\n"
            "\n"
            "    ... your settings ...\n"
            "\n"
            "    return config\n"
            "\n"
            "or load the theme yourself wherever it suits you, with:\n"
            f"\n"
            f"    dofile({module!r})(config)\n"
        )

    with open(path, "w") as fh:
        fh.write(text)

    print(status)


if __name__ == "__main__":
    main()
