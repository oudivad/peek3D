<img src="docs/images/icon.png" width="96" align="right" alt="">

# Peek3D

Press space on an `.stl`, `.obj`, `.ply`, `.3mf`, `.step` or `.iges` file in the
Finder, and the part shows up and turns. Drag it to rotate, pinch to zoom, press
space again to put it away.

### [Download the latest release](https://github.com/oudivad/peek3D/releases/latest)

19 MB, macOS 13 or later, Apple Silicon. Drag Peek3D into Applications and open
it once. That first launch is what makes macOS notice the preview extension;
after it you can quit the app and forget it is there.

Two things look like bugs and are not. macOS refuses the first launch, because
Peek3D is not notarized and notarizing needs a paid Apple certificate: allow it
once under System Settings › Privacy & Security › Open Anyway. And open it from
Applications rather than from the mounted disk image, because launched from the
image the extension registers at a path that vanishes the moment you eject it.

STEP and IGES are the interesting ones. They hold no triangles at all, only
exact surfaces, so Peek3D carries OpenCASCADE to work out what to draw. On a
part dense enough that drawing every triangle would be a smear, the wireframe
can show only the edges where the surface actually turns.

[How it works](docs/design.md) · [Building from source](docs/building.md) ·
[Known limitations](docs/limitations.md)

MIT licensed. Ships OpenCASCADE, see the [third-party notices](THIRD-PARTY.md).
