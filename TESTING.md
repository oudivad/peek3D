# Trying Peek3D

Thanks for testing. This takes about three minutes.

Peek3D adds 3D previews to the Finder: select a model, press **space**, and the
part appears and turns. It handles `.stl`, `.obj`, `.ply`, `.3mf`, `.step` and
`.iges`.

## 1. Install

Open `Peek3D.dmg` and drag **Peek3D** onto the **Applications** shortcut.

Then open it from **Applications**, not from the disk image — and eject the
image. Launched from the image, Peek3D registers its extension at a path on
that volume, and previews break as soon as you eject it.

## 2. Get past Gatekeeper

Peek3D is not notarized — that needs a paid Apple certificate — so macOS will
refuse to open it the first time and say it cannot verify the developer.
This is expected, and here is how to allow it:

1. Double-click **Peek3D** in Applications. You get a warning. Click **Done**.
2. Open **System Settings › Privacy & Security**.
3. Scroll down. A line mentions Peek3D was blocked. Click **Open Anyway**.
4. Confirm.

The app must be launched **once** for macOS to discover its preview extension.
After that you can quit it; previews keep working.

## 3. Let Peek3D take over (optional)

On first launch Peek3D asks whether it should handle STL, OBJ and PLY too.
macOS already previews those with its own extension, which takes precedence
otherwise.

Saying yes sets aside Apple's extension, which also covers USD, USDZ and
Alembic — those will then be shown by a cruder system extension. The setting is
reversible at any time from the **Peek3D** menu.

Formats nobody else claims — STEP, IGES, 3MF — are handled either way.

## 4. Try it

The disk image has a **Samples** folder. Copy it somewhere, then in the Finder:

- select `manifold.step` and press **space** — a deliberately awkward part:
  a knurled boss, sixteen counterbored holes, thirty-five thousand triangles.
  Switch the wireframe between *all triangles* and *sharp edges* and compare;
- select `bracket.step` — a filleted part, which has no sharp edge anywhere,
  so that mode draws nothing on it. That is geometry, not a fault;
- drag inside the preview to rotate it, scroll to zoom;
- leave it alone and it turns slowly on its own;
- try `sphere.stl`, `cube.obj`, `cube.3mf` as well.

Also try your own files, especially large ones.

## What to report back

- Your macOS version (Apple menu › About This Mac) and Mac model.
- Anything that failed to open, with the file if you can share it.
- Anything slow: how long before the preview appears.
- Anything that looks wrong: faceted where it should be smooth, rounded where
  it should be sharp, inside-out, off-centre.
- Whether the Finder shows 3D icons for these files, or generic document icons.

## Removing it

Drag Peek3D from Applications to the Trash. If you enabled the handover in
step 3, undo it first from the Peek3D menu, or run:

```sh
pluginkit -e use -i com.apple.HydraQLPreviewExtension
```
