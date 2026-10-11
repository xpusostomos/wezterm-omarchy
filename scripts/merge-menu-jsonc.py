#!/usr/bin/env python3
"""Add a WezTerm row to Omarchy's menu extension file.

Omarchy's default-terminal selector is not shipped in a script -- it is data, in
omarchy-menu.jsonc. The user file at
~/.config/omarchy/extensions/omarchy-menu.jsonc is merged on top of the defaults,
which makes it the supported place to add a row and keeps this out of a
package-owned file.

That file belongs to the user (it ships as a page of comments and examples), so
this edits it in place rather than replacing it, inserting one member before the
closing brace. The block is marker-delimited and the insertion is exactly
reversible, so re-running is idempotent and uninstall leaves the file
byte-identical to how it started.

The shell parses this file at startup and watches it for changes, so a broken
file would take the whole menu with it: the result is parsed before anything is
written, and nothing is written if it does not parse.

usage: merge-menu-jsonc.py <file> <action> [--remove]
"""

import json
import os
import re
import sys

MARK = "wezterm-omarchy"
START = f"// >>> {MARK}"
END = f"// <<< {MARK}"
ROW_ID = "setup.default.terminal.wezterm"


def strip_jsonc(text):
    """Remove // comments, respecting string literals."""
    out = []
    for line in text.splitlines():
        in_string = False
        escaped = False
        for i, ch in enumerate(line):
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == '"':
                in_string = not in_string
                continue
            if not in_string and line[i : i + 2] == "//":
                line = line[:i]
                break
        out.append(line)
    return "\n".join(out)


def parses(text):
    stripped = strip_jsonc(text)
    try:
        json.loads(stripped)
        return True
    except json.JSONDecodeError:
        # A trailing comma before the closing brace is common in hand-written
        # JSONC and the shell's parser tolerates it, so accept that rather than
        # reject a file over punctuation it already contains.
        relaxed = re.sub(r",(\s*[}\]])", r"\1", stripped)
        try:
            json.loads(relaxed)
            return True
        except json.JSONDecodeError:
            return False


def build_row(reference, action):
    """The menu row.

    `reference` is the shipped default menu, not the user's file -- the user file
    holds only their extensions, so the stock rows are not in it. The icon is
    read from there so this repo never has to carry a Nerd Font codepoint.

    `checked` reads the live default rather than asking omarchy-default-terminal,
    so the tick is right whether or not the system script has been taught about
    WezTerm.
    """
    icon = ""
    m = re.search(
        r'"setup\.default\.terminal\.foot"\s*:\s*\{[^}]*"icon"\s*:\s*"([^"]*)"', reference
    )
    if m:
        icon = m.group(1)

    fields = [
        f'"icon":"{icon}"',
        '"label":"WezTerm"',
        '"when":"omarchy-cmd-present wezterm"',
        '"checked":"[[ \\"$(xdg-terminal-exec --print-id 2>/dev/null)\\" '
        '== org.wezfurlong.wezterm.desktop ]]"',
        f'"action":"{action}"',
    ]
    return f'"{ROW_ID}": {{' + ",".join(fields) + "}"


def insert(text, reference, action):
    # Index of the closing brace. rstrip only truncates the end of the string and
    # the brace is the last non-whitespace character, so the index is valid in the
    # original text too.
    close = text.rstrip().rfind("}")
    if close < 0:
        sys.exit("refusing to edit: no closing brace")

    # head is deliberately NOT rstripped. Trimming it would delete the whitespace
    # that was already before the brace, which removal could never put back, so
    # uninstall would not restore the file byte for byte.
    head, tail = text[:close], text[close:]

    # A separator is needed only when the object already holds a member that does
    # not end in a comma. Checked against comment-stripped text, so a comma inside
    # a comment (which the shipped file is full of) does not count.
    before = strip_jsonc(head).rstrip()
    comma = "" if before.endswith("{") or before.endswith(",") else ",\n"

    # The separator gets its own line and the marker records whether one was
    # added, so removal can take back exactly this and nothing else.
    marker = f"{START} sep={'yes' if comma else 'no'}"
    return f"{head}\n{comma}{marker}\n{build_row(reference, action)}\n{END}\n{tail}"


def remove(text):
    # The leading newline, the optional separator line, the block, and the
    # trailing newline -- exactly what insert() wrote, and no more. Anchoring on
    # the newline immediately before the separator or marker is what stops this
    # reaching back into a comment line that happens to end in a comma.
    pattern = r"\n(?:,\n)?" + re.escape(START) + r" sep=\S+\n.*?" + re.escape(END) + r"\n?"
    if not re.search(pattern, text, flags=re.S):
        # Tolerate a hand-edited or older block by falling back to the block only.
        pattern = re.escape(START) + r".*?" + re.escape(END) + r"\n?"
    return re.sub(pattern, "", text, flags=re.S)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)

    target, action = sys.argv[1], sys.argv[2]
    removing = "--remove" in sys.argv[3:]

    try:
        with open("/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc") as fh:
            reference = fh.read()
    except OSError:
        reference = ""

    try:
        with open(target) as fh:
            text = fh.read()
    except FileNotFoundError:
        if removing:
            sys.exit(0)
        text = "{\n}\n"

    if START in text:
        if removing:
            text = remove(text)
        else:
            # Remove then insert, rather than replacing the block in place: the
            # separator before it depends on what precedes it, so a targeted
            # rewrite would leave the marker's sep flag disagreeing with reality
            # and drift a little on every run.
            text = insert(remove(text), reference, action)
    elif removing:
        sys.exit(0)
    else:
        text = insert(text, reference, action)

    if not parses(text):
        sys.exit(f"refusing to write {target}: the result would not parse")

    # A fresh account has no extensions directory yet.
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w") as fh:
        fh.write(text)


if __name__ == "__main__":
    main()
