# Peek3D

3D previews in the Finder. Select an `.stl`, `.obj`, `.ply`, `.3mf`, `.step` or
`.iges` file, press **space**, and the part appears and turns. Drag to rotate,
pinch to zoom, press space again to dismiss.

### → [**Download the latest release**](https://github.com/oudivad/peek3d/releases/latest)

Drag **Peek3D** onto Applications and open it once — that is when macOS finds
the preview extension. You can quit it straight away. Requires **macOS 13 or
later**, on Apple Silicon.

Two things that will otherwise look like faults:

- **The first launch is refused.** Peek3D is not notarized, so macOS says it
  cannot verify the developer. Allow it once under **System Settings › Privacy
  & Security › Open Anyway**.
- **Do not run it from the mounted disk image.** The extension would register
  at a path on that volume, and previews break the moment you eject it.

| | |
|---|---|
| [How it works](docs/design.md) | the formats, the CAD kernel, why previews are contested |
| [Building from source](docs/building.md) | no Xcode needed; signing and releases |
| [Known limitations](docs/limitations.md) | what it does not do, and why |

MIT, see [LICENSE](LICENSE). Ships OpenCASCADE — [third-party notices](THIRD-PARTY.md).
