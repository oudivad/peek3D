#!/bin/bash
# Build OpenCASCADE from source, for releases.
#
# Why not simply use the Homebrew package? Because it is compiled for the macOS
# version of the machine that installs it. An application embedding it inherits
# that constraint and refuses to start on anything older — which shows up only
# on a user's Mac, never on your own.
#
# This script produces an OpenCASCADE trimmed to the modules needed to read STEP
# and IGES, targeting a chosen macOS version.
#
# Usage: scripts/build-occt.sh [minimum-macOS-version] [directory]
set -euo pipefail

MACOS_MIN="${1:-13.0}"
PREFIX="${2:-$PWD/vendor/occt}"
VERSION="V7_9_3"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v cmake >/dev/null || { echo "cmake is required: brew install cmake" >&2; exit 1; }

echo "→ fetching OpenCASCADE $VERSION"
git clone --depth 1 --branch "$VERSION" \
    https://github.com/Open-Cascade-SAS/OCCT.git "$WORK/occt"

echo "→ configuring (targeting macOS $MACOS_MIN)"
# Only the data-exchange and meshing modules matter here. Everything else —
# visualization, sample applications, side formats — would add hundreds of
# megabytes without contributing anything to a preview.
cmake -S "$WORK/occt" -B "$WORK/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DBUILD_LIBRARY_TYPE=Shared \
    -DBUILD_MODULE_ApplicationFramework=ON \
    -DBUILD_MODULE_DataExchange=ON \
    -DBUILD_MODULE_FoundationClasses=ON \
    -DBUILD_MODULE_ModelingAlgorithms=ON \
    -DBUILD_MODULE_ModelingData=ON \
    -DBUILD_MODULE_Visualization=OFF \
    -DBUILD_MODULE_Draw=OFF \
    -DBUILD_DOC_Overview=OFF \
    -DUSE_TBB=OFF \
    -DUSE_FREETYPE=OFF \
    -DUSE_FREEIMAGE=OFF \
    -DUSE_OPENGL=OFF \
    -DUSE_RAPIDJSON=OFF \
    -DUSE_DRACO=OFF

echo "→ compiling (allow 20 to 40 minutes)"
cmake --build "$WORK/build" --parallel "$(sysctl -n hw.ncpu)"
cmake --install "$WORK/build"

# The Makefile reads this marker and then picks up this installation, and its
# macOS version, on its own. Without it you can build against an OpenCASCADE
# targeting macOS 13 while declaring a requirement of macOS 26, or the reverse —
# an inconsistency invisible until it reaches a user.
echo "$MACOS_MIN" > "$PREFIX/.macos-min"

echo
echo "✓ OpenCASCADE installed in $PREFIX"
echo
if [ "$PREFIX" = "$PWD/vendor/occt" ]; then
    echo "  \"make app\" will now use it automatically, targeting macOS $MACOS_MIN."
else
    echo "  Build Peek3D with:"
    echo "    make app OCCT_PREFIX=$PREFIX MACOS_MIN=$MACOS_MIN"
fi
