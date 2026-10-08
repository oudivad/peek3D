import Foundation
import AppKit
import UniformTypeIdentifiers

/// Taking over the formats macOS already previews.
///
/// Three Quick Look extensions compete for 3D files: the Pixar one Apple ships
/// (`Hydra`, which handles USD and claims STL, OBJ and PLY along the way), the
/// SceneKit one (which claims all of `public.3d-content`), and ours. When the
/// declared types are equally specific the system extension wins, and since
/// `showsInExtensionsManager` is false for both, they do not even appear in
/// System Settings.
///
/// The only lever is PlugInKit's *election*: a per-user preference that needs
/// no administrator privilege and is as easily undone as it is set.
@MainActor
enum PreviewHandover {

    /// Apple's extension, which precedes ours on STL, OBJ and PLY.
    static let systemExtensionID = "com.apple.HydraQLPreviewExtension"

    /// Formats it claims that Peek3D can read. USD, USDZ, Alembic and MaterialX
    /// are on its list too; we do not handle those, which is precisely what
    /// makes this switch optional rather than automatic.
    static let contestedFormats = ["STL", "OBJ", "PLY"]

    /// Formats surrendered by setting the system extension aside. They do not
    /// vanish: the SceneKit extension, cruder but present, takes over.
    static let surrenderedFormats = ["USD", "USDZ", "Alembic", "MaterialX"]

    private static let pluginkit = URL(fileURLWithPath: "/usr/bin/pluginkit")

    /// Formats macOS already entrusts to Preview. The others — STEP, IGES, 3MF —
    /// have no designated opener and fall to Peek3D with nothing to set.
    private static let contestedTypes = [
        "public.standard-tesselated-geometry-format",
        "public.geometry-definition-format",
        "public.polygon-file-format",
    ]

    /// The application to hand these formats back to.
    private static let systemViewer = URL(fileURLWithPath: "/System/Applications/Preview.app")

    /// Remembers that the question has been asked, so it is not asked again at
    /// every launch.
    private static let askedKey = "PreviewHandoverAsked"

    // MARK: State

    /// True when Peek3D has priority, that is, when the system extension has
    /// been set aside.
    static var isPeek3DPreferred: Bool {
        // `-A` includes disabled extensions; without it, one that has been set
        // aside would simply vanish from the listing.
        guard let output = run(["-mA", "-i", systemExtensionID]) else { return false }
        // The first column carries the election: "-" for an extension set aside,
        // "+" for one explicitly kept, blank by default.
        return output.split(separator: "\n").contains { $0.hasPrefix("-") }
    }

    // MARK: Default opener

    /// True if an earlier version of Peek3D made itself the opener of these
    /// formats.
    static var isPeek3DDefaultOpener: Bool {
        let ours = Bundle.main.bundleURL.resolvingSymlinksInPath()
        return contestedTypes.allSatisfy { identifier in
            guard let type = UTType(identifier),
                  let current = NSWorkspace.shared.urlForApplication(toOpen: type) else {
                return false
            }
            return current.resolvingSymlinksInPath() == ours
        }
    }

    /// Hands these formats back to Preview.
    ///
    /// Peek3D briefly declared itself the opener, back when it displayed models
    /// in a window. That window is gone — it duplicated the preview — and
    /// letting a double-click land on an app that shows nothing would be worse
    /// than doing nothing at all.
    static func restoreSystemOpener() async {
        let target = systemViewer
        guard FileManager.default.fileExists(atPath: target.path) else { return }

        for identifier in contestedTypes {
            guard let type = UTType(identifier) else { continue }
            // The API is asynchronous and may refuse — a type the user has
            // pinned, for instance. That is no reason to stop: the remaining
            // formats still deserve a try.
            try? await NSWorkspace.shared.setDefaultApplication(at: target, toOpen: type)
        }
    }

    // MARK: Switching

    @discardableResult
    static func setPeek3DPreferred(_ preferred: Bool) -> Bool {
        guard run(["-e", preferred ? "ignore" : "use", "-i", systemExtensionID]) != nil else {
            return false
        }
        // Quick Look caches its previews: without a purge, the change only shows
        // on the next file never seen before.
        //
        // Crucially, we do not wait for it. `qlmanage` regularly hangs for
        // minutes, and waiting on the main thread freezes the whole interface
        // into a blank window.
        let qlmanage = Process()
        qlmanage.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        qlmanage.arguments = ["-r", "cache"]
        qlmanage.standardOutput = FileHandle.nullDevice
        qlmanage.standardError = FileHandle.nullDevice
        try? qlmanage.run()
        return true
    }

    // MARK: First-launch offer

    static var hasBeenAsked: Bool {
        UserDefaults.standard.bool(forKey: askedKey)
    }

    /// Offers the switch once, at first launch. It is offered and not imposed:
    /// disabling an Apple extension behind the user's back would be an
    /// overreach, and the surrendered formats matter to some people.
    static func offerIfNeeded() {
        guard !hasBeenAsked, !(isPeek3DPreferred && isPeek3DDefaultOpener) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)

        let alert = NSAlert()
        alert.messageText = L("handover.title")
        alert.informativeText = L("handover.body",
                                  contestedFormats.joined(separator: ", "),
                                  surrenderedFormats.joined(separator: ", "))
        alert.addButton(withTitle: L("handover.accept"))
        alert.addButton(withTitle: L("handover.decline"))
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            if !setPeek3DPreferred(true) {
                let failure = NSAlert()
                failure.messageText = L("handover.failed")
                failure.informativeText = L("handover.failed.body", "ignore", systemExtensionID)
                failure.runModal()
            }
        }
    }

    // MARK: Calling pluginkit

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = pluginkit
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
