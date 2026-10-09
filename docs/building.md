# Building Peek3D

Only needed if you want to change Peek3D. To simply use it, take the disk image
from the [latest release](https://github.com/oudivad/peek3d/releases/latest).

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
you, so your users have to say they trust you once. Two routes:

1. **Approve it once.** The user drags the app to /Applications, opens it, and
   allows it under System Settings › Privacy & Security › *Open Anyway*. Or, in
   one command:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Peek3D.app
   ```

   A Homebrew cask installed with `--no-quarantine` would skip the prompt
   altogether, since the quarantine flag is what triggers it. That means a
   second repository to keep in step with every release, which is a real cost
   for a one-off download.

2. **Developer ID and notarization** ($99/year). No prompt, no instructions to
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
