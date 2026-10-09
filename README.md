<p align="center">
  <img src="docs/images/icon.png" width="128" alt="">
</p>

<h1 align="center">Peek3D</h1>

<p align="center">Quick Look previews for 3D and CAD files on macOS.</p>

<p align="center">
  <img src="docs/images/demo.gif" width="860" alt="Previewing a STEP file in the Finder: wireframe modes, zooming into the mesh, changing the surface colour.">
</p>

---

Press space on an `.stl`, `.obj`, `.ply`, `.3mf`, `.step` or `.iges` file in the
Finder. The part renders and turns. Drag to rotate, pinch to zoom.

**[Download the latest release](https://github.com/oudivad/peek3D/releases/latest)**  19 MB · macOS 13+ · Apple Silicon

Drag into Applications, open once to register the extension, quit, done.

### First launch

Not notarized, so macOS blocks it. Approve under System Settings › Privacy &
Security › Open Anyway.

Run it from Applications.

### STEP and IGES

Exact surfaces, not meshes. Tessellated with OpenCASCADE, bundled as dylibs.

On a dense part the wireframe draws sharp edges only (faces meeting above 25°,
plus open borders) which stays readable where a full triangle mesh does not.

---

[How it works](docs/design.md) · [Build](docs/building.md) · [Limitations](docs/limitations.md)

MIT. Ships OpenCASCADE under LGPL 2.1 with the OCCT exception
([notices](THIRD-PARTY.md)).
