# How Peek3D works

Supported formats:

| Format | Extensions | Kind |
|---|---|---|
| STL | `.stl` | mesh, binary and ASCII |
| Wavefront | `.obj` | mesh |
| Stanford PLY | `.ply` | mesh, ASCII and binary |
| 3MF | `.3mf` | mesh, with scene graph and transforms |
| STEP | `.step` `.stp` | CAD, exact surfaces |
| IGES | `.iges` `.igs` | CAD, exact surfaces |

The first four already contain triangles. The last two describe mathematical
surfaces — planes, cylinders, NURBS — that must be evaluated before anything
can be drawn. Peek3D embeds [OpenCASCADE](https://dev.opencascade.org) for
that, the geometry kernel behind much of the open-source CAD world.

## Architecture

```
Sources/
  Peek3DKit/            file loaders, rendering, shared view
  OCCTBridge/           C interface over OpenCASCADE (C++)
  Peek3DApp/            host app: window, drag and drop
  QuickLookExtension/   the spacebar preview
  ThumbnailExtension/   Finder thumbnails
```

Three choices shape the rest.

**Normals are recomputed with a crease angle.** An STL holds nothing but loose
triangles. Welding them naively and averaging normals rounds the edges of a
machined part; welding nothing facets curved surfaces. Peek3D instead groups
the faces meeting at a point by orientation: beyond 35° apart they get separate
normals. A cube keeps crisp edges, a sphere stays smooth.

**Everything is normalized to a unit sphere.** Models range from microns to
metres. Centering and scaling before display avoids both part-dependent camera
settings and float precision loss at the extremes.

**Loading code is shared, and so are the libraries.** Each extension embeds the
same Swift code, but OpenCASCADE exists in a single copy under
`Contents/Frameworks`, referenced through `@rpath`. The whole app is about
forty megabytes.

## Taking over the formats macOS already previews

macOS can already preview STL, OBJ and PLY — badly, but it can. Three
extensions then compete for the file: the Pixar one Apple ships for USD
(`HydraQLPreviewExtension`), which claims those three formats along the way;
the SceneKit one, which claims all of `public.3d-content`; and Peek3D. When the
declared types are equally specific the system extension wins, and both are
marked `showsInExtensionsManager = false`, so they don't even appear in System
Settings.

The only lever is PlugInKit's *election*, a per-user preference that needs no
administrator privilege. Peek3D offers it on first launch, and the setting
stays available under **Peek3D › Use Peek3D for STL, OBJ and PLY**.

A second, independent setting controls the **Open with…** button in the preview
panel and what a double-click in the Finder does. That one is the default
application registered for the file type, which macOS gives to Preview.app for
STL, OBJ and PLY. **Peek3D › Open STL, OBJ and PLY with Peek3D** claims it, and
unchecking hands it back to Preview.

On the command line the preview election amounts to:

```sh
pluginkit -e ignore -i com.apple.HydraQLPreviewExtension   # Peek3D goes first
pluginkit -e use    -i com.apple.HydraQLPreviewExtension   # back to macOS
qlmanage -r cache                                          # drop cached previews
```

Know the trade: Apple's extension also handles USD, USDZ, Alembic and
MaterialX, which Peek3D does not read. Once it is set aside, those files fall
back to the SceneKit extension — cruder, but working. The formats nobody else
claims — STEP, IGES, 3MF — are Peek3D's with no setting at all.
