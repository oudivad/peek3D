# Homebrew cask.
#
# This file does not belong in this repository as such: Homebrew looks for
# recipes in a repository whose name starts with "homebrew-". Copy it into an
# oudivad/homebrew-tap repository, as Casks/peek3d.rb. The install address is
# then written user/tap/cask:
#
#   brew install --cask --no-quarantine oudivad/tap/peek3d
#
# The middle word is the repository of recipes, the last one the recipe itself.
# No need to run "brew tap" first: Homebrew does it on sight of a three-part
# address.
#
# The application is not notarized (Apple's Developer ID certificate costs
# $99/year), so Gatekeeper rejects it on download. --no-quarantine avoids the
# warning by not attaching the attribute that triggers it. Without that flag the
# user has to allow the application once from System Settings > Privacy &
# Security.
cask "peek3d" do
  version "1.0.0"
  # Checksum of the .dmg attached to the matching GitHub release. Recompute it
  # for every version with:  shasum -a 256 Peek3D-<version>.dmg
  sha256 "8233027e05a21bc681cf7fa9ec984599a6758fa379d9d32a3b470879c205dd3c"

  url "https://github.com/oudivad/peek3d/releases/download/v#{version}/Peek3D-#{version}.dmg"
  name "Peek3D"
  desc "Quick Look previews for 3D models and CAD files"
  homepage "https://github.com/oudivad/peek3d"

  depends_on macos: ">= :ventura"

  app "Peek3D.app"

  # macOS only discovers extensions at the first launch of the application
  # containing them.
  postflight do
    system_command "/System/Library/Frameworks/CoreServices.framework/Frameworks/" \
                   "LaunchServices.framework/Support/lsregister",
                   args: ["-f", "#{appdir}/Peek3D.app"]
  end

  zap trash: [
    "~/Library/Caches/io.github.oudivad.Peek3D",
    "~/Library/Preferences/io.github.oudivad.Peek3D.plist",
  ]
end
