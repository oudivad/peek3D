#!/bin/bash
# Embed the dynamic libraries a bundle pulls in from Homebrew.
#
# OpenCASCADE binaries installed by Homebrew are not loadable on a machine that
# has no Homebrew: they refer to each other either by absolute path
# (/opt/homebrew/...) or through @rpath, which only means anything with the
# original search paths. We therefore copy the transitive closure of the
# dependencies into Contents/Frameworks and rewrite every reference to @rpath,
# which the bundle resolves relative to its own executable.
#
# Usage: bundle-libs.sh <binary> <Frameworks> <search-dir>...
set -eo pipefail

binary="$1"; shift
frameworks="$1"; shift
search_dirs=("$@")

mkdir -p "$frameworks"

# Locate a dependency expressed as @rpath among the directories given.
resolve_rpath() {
    local name="$1"
    for dir in "${search_dirs[@]}"; do
        if [ -f "$dir/$name" ]; then echo "$dir/$name"; return 0; fi
    done
    return 1
}

# The presence of an already-copied file serves as the "seen" marker: macOS only
# ships bash 3.2, which has no associative arrays.
queue=("$binary")
count=0

while [ ${#queue[@]} -gt 0 ]; do
    current="${queue[0]}"
    queue=("${queue[@]:1}")

    while read -r dep; do
        [ -z "$dep" ] && continue
        name="$(basename "$dep")"
        source=""

        case "$dep" in
            /opt/homebrew/*|/usr/local/*)
                source="$dep" ;;
            @rpath/*)
                # Libraries already embedded are where they belong.
                [ -f "$frameworks/$name" ] && continue
                source="$(resolve_rpath "$name")" || continue ;;
            *)
                # /usr/lib and /System come with macOS: never copy those.
                continue ;;
        esac

        if [ ! -f "$frameworks/$name" ]; then
            # `cp -L` follows symlinks: Homebrew exposes each library under three
            # names, and only the real file is wanted.
            cp -L "$source" "$frameworks/$name"
            chmod u+w "$frameworks/$name"
            install_name_tool -id "@rpath/$name" "$frameworks/$name" 2>/dev/null
            queue=("${queue[@]}" "$frameworks/$name")
            count=$((count + 1))
        fi

        # No need to rewrite an @rpath reference: it is already in the right form.
        case "$dep" in
            @rpath/*) ;;
            *) install_name_tool -change "$dep" "@rpath/$name" "$current" 2>/dev/null || true ;;
        esac
    done < <(otool -L "$current" | tail -n +2 | awk '{print $1}')
done

# install_name_tool invalidates the signature of every file it touches; the
# Makefile re-signs them once the bundle is complete.
echo "  $count libraries embedded"
