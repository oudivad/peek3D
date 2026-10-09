# Peek3D

3D model previews in the Finder. Select a file, press **space**, and the part
appears and turns. Drag to rotate it, scroll to zoom, press space again to
dismiss. Nothing to open, nothing to launch.

## Download

### → [**Get the latest release**](https://github.com/oudivad/peek3d/releases/latest)

Grab `Peek3D-1.0.0.dmg` from **Releases**, in the sidebar on the right of this
page. **There is nothing to build.** Open the disk image, drag **Peek3D** onto
**Applications**, then launch it once — that is when macOS discovers the
preview extension. You can quit it straight away; previews keep working.

> **Do not run Peek3D from the mounted disk image.** Drag it to Applications
> first, then open it from there. Launching it from the image registers the
> extension at a path on that volume; once the image is ejected the path is
> gone, and previews fail with "the extension could not be found".

Requires **macOS 13 (Ventura) or later**, on Apple Silicon.

> **The first launch will be refused.** Peek3D is not notarized — that needs a
> paid Apple certificate — so macOS says it cannot verify the developer. Allow
> it once under **System Settings › Privacy & Security › Open Anyway**, and you
> will not be asked again. The [Signing](#signing-and-what-it-costs) section
> explains why, and what the alternatives are.

Or, with Homebrew:

```sh
brew install --cask --no-quarantine oudivad/tap/peek3d
```

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

## Build from source

Only needed if you want to change Peek3D. To simply use it, take the disk image
above.


Xcode is not required; the Command Line Tools are enough.

```sh
xcode-select --install          # if you haven't already
brew install opencascade
make app
```

| Command | Effect |
|---|---|
| `make app` | builds `build/Peek3D.app` |
| `make test` | runs the loaders against `Tests/fixtures` |
| `make icon` | regenerates `Resources/AppIcon.icns` |
| `make dmg` | packages the disk image |
| `make reset-quicklook` | clears the preview cache while developing |

Useful variables: `VERSION`, `BUNDLE_ID`, `MACOS_MIN`, `CODESIGN_ID`,
`OCCT_PREFIX`.

### Installing your build

```sh
make install
```

Then launch the app **once**: that is when macOS discovers a Quick Look
extension. You can close the window afterwards — it is only useful for
studying a model longer than a preview allows.

Since macOS 14, installed applications are protected against changes made from
a terminal. If `make install` cannot replace an earlier copy, either drag
Peek3D from /Applications to the Trash in the Finder, or allow your terminal
under System Settings › Privacy & Security › App Management.

To remove: `make uninstall`.

### Shipping a release

Two things deserve attention before you publish an archive.

**The minimum macOS version.** Homebrew's OpenCASCADE is built for the macOS
version of the machine that installs it. An app that embeds it inherits that
constraint and refuses to start on anything older — something you never see on
your own machine, only on your users'. Hence:

```sh
scripts/build-occt.sh 13.0              # allow 20 to 40 minutes
make app OCCT_PREFIX=$PWD/vendor/occt MACOS_MIN=13.0
```

#### Signing, and what it costs

The default signature is ad hoc, which costs nothing. Gatekeeper then rejects
both the app and the disk image:

```
$ spctl -a -t exec -vv /Applications/Peek3D.app
/Applications/Peek3D.app: rejected
```

That does *not* prevent distribution — it only means macOS will not vouch for
you, so your users have to say they trust you. Three routes, in increasing
order of cost:

1. **Homebrew without quarantine.** The quarantine flag is what triggers the
   Gatekeeper prompt; skipping it removes the friction entirely, at the price
   of asking users to trust the tap.

   ```sh
   brew install --cask --no-quarantine oudivad/tap/peek3d
   ```

   The address reads *user / tap / cask*: the middle part is the repository
   holding the recipes, which Homebrew expects to be named `homebrew-tap`, and
   the last word is the recipe. No `brew tap` beforehand — Homebrew taps on
   sight of a three-part address. `Casks/peek3d.rb` here is the recipe to copy
   into that repository.

2. **Plain download.** The user drags the app to /Applications, then approves
   it once under System Settings › Privacy & Security › *Open Anyway*. Or, in
   one command:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Peek3D.app
   ```

3. **Developer ID and notarization** ($99/year). No prompt, no instructions to
   read, nothing to explain. This is what most polished Mac apps do, free ones
   included — their maintainer or sponsor pays for it.

   ```sh
   make app CODESIGN_ID="Developer ID Application: Your Name (XXXXXXXXXX)"
   xcrun notarytool submit Peek3D.dmg --keychain-profile peek3d --wait
   xcrun stapler staple Peek3D.dmg
   ```

An ad-hoc signature is enough for the Quick Look extension itself to load:
verified here with the extension serving previews from an unnotarized build.
What the certificate buys is the absence of a scary dialog, not the ability to
run.

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

## Known limitations

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

## Licence

MIT, see [LICENSE](LICENSE). Peek3D embeds OpenCASCADE Technology, under
LGPL 2.1 with the OCCT exception.
