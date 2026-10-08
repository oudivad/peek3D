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
trap 'rm -f "$log"' EXIT

# A cached preview would be served without launching anyone.
(qlmanage -r cache >/dev/null 2>&1 &)
killall -9 quicklookd QuickLookUIService 2>/dev/null || true
sleep 1

log stream --style compact \
    --predicate 'composedMessage CONTAINS "Launching extension"' > "$log" 2>&1 &
watcher=$!
sleep 2

(qlmanage -p "$file" >/dev/null 2>&1 &)
sleep 6
pkill -f "qlmanage -p" 2>/dev/null || true
kill "$watcher" 2>/dev/null || true
sleep 1

served="$(grep -o 'Launching extension [A-Za-z0-9.]*' "$log" | sed 's/Launching extension //' | sort -u)"

echo "File      : $(basename "$file")"
echo "Type (UTI): $(mdls -raw -name kMDItemContentType "$file" 2>/dev/null)"
if [ -z "$served" ]; then
    echo "Extension : none — macOS found nobody for this type"
else
    echo "Extension : $served"
fi
