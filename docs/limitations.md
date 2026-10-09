# Known limitations

- **Finder thumbnails.** The preview extension works; the thumbnail extension
  is in place but macOS does not yet call it reliably for CAD formats. Those
  files keep the generic document icon.
- **Default application for .3mf.** Peek3D declares a type for 3MF, which
  macOS does not know on its own. If a slicer is installed, adding that
  declaration makes LaunchServices re-rank the applications claiming `.3mf`,
  and the default opener may change — from Bambu Studio to OrcaSlicer, for
  instance. Set it back from the Finder: select a file, **Get Info**, then
  **Open with › Change All**.
- **Sharp edges on a fully filleted part.** The wireframe's *sharp edges* mode
  draws where the surface turns. A part whose every edge is rounded has none —
  each face meets the next tangentially — so that mode shows nothing on it. Use
  *all triangles* there, or read the shading.
- **USD, USDZ, Alembic.** Not read by Peek3D. If you enable the handover above,
  the system's SceneKit extension shows them instead.
- **Apple Silicon only.** The build targets `arm64`. A universal binary would
  need OpenCASCADE compiled for both architectures.
- **OBJ without materials.** Only geometry is read; `.mtl` files and textures
  are ignored, and unreachable from a sandboxed extension anyway.
- **Concave polygons.** Fan triangulation is fine for convex polygons, which
  are the overwhelming majority; a strongly concave one may render wrong.
