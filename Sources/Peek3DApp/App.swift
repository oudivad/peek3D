import AppKit
import UniformTypeIdentifiers

/// Peek3D is not a viewer. Everything happens in the Finder, on the space bar,
/// and this application exists only because macOS refuses to discover a Quick
/// Look extension any other way: it must ship inside an app that is installed
/// and launched at least once.
///
/// Its window therefore does no more than confirm everything is in place and
/// expose the system setting that decides who previews what. It did once
/// display models itself; that duplicated the preview, only slower.
@main
enum Peek3D {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var window: NSWindow?
    private let status = StatusView()
    private var handoverItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        created.title = "Peek3D"
        created.contentView = status
        created.center()
        created.setFrameAutosaveName("Peek3DStatus")
        window = created
        created.makeKeyAndOrderFront(nil)

        status.refresh()
        NSApp.activate(ignoringOtherApps: true)

        // After the window is on screen: a modal alert raised before the app is
        // visible appears out of nowhere.
        PreviewHandover.offerIfNeeded()
        status.refresh()

        // Migration: an earlier version declared itself the opener of these
        // formats. It no longer has anything to display them with.
        if PreviewHandover.isPeek3DDefaultOpener {
            Task { await PreviewHandover.restoreSystemOpener() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Double-clicking a model opens nothing: the Finder's preview already does
    /// the job and this app has no viewer. All we do is point at where to look.
    func application(_ application: NSApplication, open urls: [URL]) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        status.flashHint()
    }

    // MARK: Settings

    func menuNeedsUpdate(_ menu: NSMenu) {
        handoverItem.state = PreviewHandover.isPeek3DPreferred ? .on : .off
    }

    @objc func togglePreviewHandover() {
        let wanted = !PreviewHandover.isPeek3DPreferred
        guard PreviewHandover.setPeek3DPreferred(wanted) else {
            let alert = NSAlert()
            alert.messageText = L("handover.failed")
            alert.informativeText = L("handover.failed.body",
                                      wanted ? "ignore" : "use",
                                      PreviewHandover.systemExtensionID)
            alert.runModal()
            return
        }
        status.refresh()
    }

    // MARK: Menu

    /// An application with no nib has to build its menu bar by hand, without
    /// which even Cmd+Q does nothing.
    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("menu.about"), action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())

        handoverItem = NSMenuItem(title: L("menu.handover"),
                                  action: #selector(togglePreviewHandover), keyEquivalent: "")
        handoverItem.target = self
        appMenu.addItem(handoverItem)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.delegate = self
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("menu.window"))
        windowMenu.addItem(withTitle: L("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Peek3D"
        alert.informativeText = L("about.body",
                                  MeshDocument.allExtensions.map { ".\($0)" }.joined(separator: " "),
                                  CADLoader.openCascadeVersion)
        alert.runModal()
    }
}

/// Status panel: what Peek3D can read, and the system setting that decides who
/// previews it.
@MainActor
final class StatusView: NSView {

    private let hint = NSTextField(labelWithString: "")
    private let quickLookBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    private func build() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown

        let heading = NSTextField(labelWithString: L("status.heading"))
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.alignment = .center

        hint.stringValue = L("status.hint")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.maximumNumberOfLines = 0

        let formatsTitle = NSTextField(labelWithString: L("status.formats"))
        formatsTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        formatsTitle.textColor = .tertiaryLabelColor

        let formats = NSTextField(labelWithString:
            MeshDocument.allExtensions.map { ".\($0)" }.joined(separator: "   "))
        formats.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        formats.textColor = .secondaryLabelColor

        let settingsTitle = NSTextField(labelWithString: L("status.settings"))
        settingsTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        settingsTitle.textColor = .tertiaryLabelColor

        quickLookBox.title = L("menu.handover")
        quickLookBox.target = NSApp.delegate
        quickLookBox.action = #selector(AppDelegate.togglePreviewHandover)

        func help(_ key: String) -> NSTextField {
            let field = NSTextField(labelWithString: L(key))
            field.font = .systemFont(ofSize: 11)
            field.textColor = .tertiaryLabelColor
            field.maximumNumberOfLines = 0
            field.preferredMaxLayoutWidth = 380
            return field
        }

        let stack = NSStackView(views: [
            icon, heading, hint,
            separator(), formatsTitle, formats,
            separator(), settingsTitle,
            quickLookBox, help("status.quicklook.help"),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // The header is centred and the rest left-aligned: a settings panel
        // reads badly when everything is centred.
        for view in [icon, heading, hint] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(16, after: hint)
        stack.setCustomSpacing(16, after: formats)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
        ])
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// Reflects the real state of the system: the setting may have been changed
    /// elsewhere, from the menu or the command line.
    func refresh() {
        quickLookBox.state = PreviewHandover.isPeek3DPreferred ? .on : .off
    }

    /// Briefly highlights the instructions for someone who opened the app by
    /// double-clicking a model, expecting to see the part.
    func flashHint() {
        hint.textColor = .controlAccentColor
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.hint.textColor = .secondaryLabelColor
        }
    }
}
