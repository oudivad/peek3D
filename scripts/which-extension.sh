#!/bin/bash
# Report which Quick Look extension actually serves a given file.
#
# Indispensable when competing with an Apple extension over a format: the
# preview on screen may come from the cache, from the system or from us, and
# nothing on screen says which. The system log does.
set -eo pipefail

file="$1"
[ -f "$file" ] || { echo "usage: which-extension.sh <file>" >&2; exit 2; }

log="$(mktemp)"
work="$(mktemp -d)"
trap 'rm -rf "$log" "$work"' EXIT

# A cached preview is served without launching anyone, which would make this
# script report "none" for a file that previews perfectly well. Rather than
# restart the Quick Look daemons — killing them repeatedly gets the service
# throttled by launchd, and then nothing previews at all — ask about a copy
# under a name the cache has never seen.
probe="$work/$(date +%s)-$(basename "$file")"
cp "$file" "$probe"

log stream --style compact \
    --predicate 'composedMessage CONTAINS "Launching extension"' > "$log" 2>&1 &
watcher=$!
sleep 2

(qlmanage -p "$probe" >/dev/null 2>&1 &)
sleep 6
pkill -f "qlmanage -p" 2>/dev/null || true
kill "$watcher" 2>/dev/null || true
sleep 1

# `|| true`: no match is the very case this script exists to report, and under
# `pipefail` it would otherwise abort before printing anything.
served="$(grep -o 'Launching extension [A-Za-z0-9.]*' "$log" | sed 's/Launching extension //' | sort -u || true)"

echo "File      : $(basename "$file")"
echo "Type (UTI): $(mdls -raw -name kMDItemContentType "$probe" 2>/dev/null)"
if [ -z "$served" ]; then
    echo "Extension : none — macOS found nobody for this type"
else
    echo "Extension : $served"
fi
