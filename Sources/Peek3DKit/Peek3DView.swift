import AppKit
import SceneKit

/// The preview view used by the Quick Look extension.
///
/// It turns the part slowly while untouched — which is what conveys its volume
/// at a glance — and yields at the first gesture, resuming a few seconds later.
public class Peek3DView: NSView {

    private let sceneView = InteractiveSceneView()
    /// Background gradient, visible while no model is shown. Without it, an
    /// `SCNView` with no scene leaves a white square that looks like a bug.
    private let backdrop = CAGradientLayer()
    private let infoLabel = NSTextField(labelWithString: "")
    private let infoBackdrop = NSVisualEffectView()
    private let helpButton = NSButton()
    private let helpBackdrop = NSVisualEffectView()
    private var pivot: SCNNode?
    private let wireframeBackdrop = NSVisualEffectView()
    private let modeChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colourChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let opacitySlider = NSSlider(value: 0.65, minValue: 0.1, maxValue: 1,
                                         target: nil, action: nil)
    private let surfaceBackdrop = NSVisualEffectView()
    private let surfaceChoice = NSPopUpButton(frame: .zero, pullsDown: false)

    private var isDark = false
    /// Kept so the wireframe can be rebuilt when the mode changes, without
    /// reloading the file.
    private var currentMesh: Mesh?
    /// Finding the edges of a large mesh runs off the main thread; a newer
    /// request makes an older result stale.
    private var wireframeGeneration = 0

    /// These choices follow the viewer from one file to the next. An extension
    /// has its own defaults container, so this touches nothing else — and it
    /// cannot read the host application's settings either, which is why the
    /// controls live in the preview rather than in a preferences window.
    private static let modeKey = "WireframeMode"
    private static let colourKey = "WireframeColour"
    private static let opacityKey = "WireframeOpacity"
    private static let surfaceKey = "SurfaceStyle"
    /// Bumped on every gesture: a scheduled resume that a newer gesture has
    /// superseded is recognizable by its stale number.
    private var interactionGeneration = 0

    /// Idle rotation speed, in turns per minute. Slow enough to read the part,
    /// brisk enough to show the whole way round.
    private static let idleTurnsPerMinute = 3.0
    /// Delay before resuming after the viewer's last gesture.
    private static let resumeDelay: TimeInterval = 4

    /// Groups thousands according to the viewer's locale. `formatted(.number)`
    /// would do the same in one line, but requires macOS 12.
    private static let counter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true
        layer?.insertSublayer(backdrop, at: 0)
        updateBackdrop()

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        // Hidden until there is something to show.
        sceneView.isHidden = true
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = false
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.rendersContinuously = false
        sceneView.onInteraction = { [weak self] in self?.suspendIdleRotation() }
        addSubview(sceneView)

        infoBackdrop.translatesAutoresizingMaskIntoConstraints = false
        infoBackdrop.material = .hudWindow
        infoBackdrop.blendingMode = .withinWindow
        infoBackdrop.state = .active
        infoBackdrop.wantsLayer = true
        infoBackdrop.layer?.cornerRadius = 7
        infoBackdrop.layer?.masksToBounds = true
        infoBackdrop.isHidden = true
        addSubview(infoBackdrop)

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.maximumNumberOfLines = 1
        // In a narrow panel the info strip gives up its width to the toggle
        // rather than force the layout to break a constraint.
        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.image = NSImage(systemSymbolName: "questionmark.circle",
                                   accessibilityDescription: L("help.title"))
        helpButton.isBordered = false
        helpButton.imagePosition = .imageOnly
        helpButton.contentTintColor = .secondaryLabelColor
        helpButton.target = self
        helpButton.action = #selector(toggleHelp)
        helpButton.toolTip = L("help.title")
        helpButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let info = NSStackView(views: [helpButton, infoLabel])
        info.orientation = .horizontal
        info.spacing = 7
        info.translatesAutoresizingMaskIntoConstraints = false
        infoBackdrop.addSubview(info)

        // The help panel is drawn inside this view rather than shown in a
        // popover: an extension's panel comes and goes with the space bar, and
        // anything that opens a window of its own sits badly with that.
        helpBackdrop.translatesAutoresizingMaskIntoConstraints = false
        helpBackdrop.material = .hudWindow
        helpBackdrop.blendingMode = .withinWindow
        helpBackdrop.state = .active
        helpBackdrop.wantsLayer = true
        helpBackdrop.layer?.cornerRadius = 9
        helpBackdrop.layer?.masksToBounds = true
        helpBackdrop.isHidden = true
        addSubview(helpBackdrop)

        let helpText = NSTextField(wrappingLabelWithString: L("help.body"))
        helpText.font = .systemFont(ofSize: 11)
        helpText.textColor = .labelColor
        helpText.isSelectable = false
        helpText.translatesAutoresizingMaskIntoConstraints = false
        helpBackdrop.addSubview(helpText)

        NSLayoutConstraint.activate([
            helpBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            helpBackdrop.bottomAnchor.constraint(equalTo: infoBackdrop.topAnchor, constant: -8),
            helpBackdrop.widthAnchor.constraint(equalToConstant: 300),
            helpText.topAnchor.constraint(equalTo: helpBackdrop.topAnchor, constant: 10),
            helpText.bottomAnchor.constraint(equalTo: helpBackdrop.bottomAnchor, constant: -10),
            helpText.leadingAnchor.constraint(equalTo: helpBackdrop.leadingAnchor, constant: 12),
            helpText.trailingAnchor.constraint(equalTo: helpBackdrop.trailingAnchor, constant: -12),
        ])

        wireframeBackdrop.translatesAutoresizingMaskIntoConstraints = false
        wireframeBackdrop.material = .hudWindow
        wireframeBackdrop.blendingMode = .withinWindow
        wireframeBackdrop.state = .active
        wireframeBackdrop.wantsLayer = true
        wireframeBackdrop.layer?.cornerRadius = 7
        wireframeBackdrop.layer?.masksToBounds = true
        wireframeBackdrop.isHidden = true
        addSubview(wireframeBackdrop)

        func popup(_ control: NSPopUpButton, _ action: Selector) {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.controlSize = .small
            control.font = .systemFont(ofSize: 11)
            control.target = self
            control.action = action
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        popup(modeChoice, #selector(changeWireframeMode))
        for mode in WireframeMode.allCases {
            modeChoice.addItem(withTitle: mode.label)
            modeChoice.lastItem?.representedObject = mode.rawValue
        }

        popup(surfaceChoice, #selector(changeSurface))
        for surface in SurfaceStyle.allCases {
            surfaceChoice.addItem(withTitle: surface.label)
            surfaceChoice.lastItem?.representedObject = surface.rawValue
        }

        surfaceBackdrop.translatesAutoresizingMaskIntoConstraints = false
        surfaceBackdrop.material = .hudWindow
        surfaceBackdrop.blendingMode = .withinWindow
        surfaceBackdrop.state = .active
        surfaceBackdrop.wantsLayer = true
        surfaceBackdrop.layer?.cornerRadius = 7
        surfaceBackdrop.layer?.masksToBounds = true
        surfaceBackdrop.isHidden = true
        addSubview(surfaceBackdrop)
        surfaceBackdrop.addSubview(surfaceChoice)

        popup(colourChoice, #selector(restyleWireframe))
        for style in WireframeStyle.allCases {
            colourChoice.addItem(withTitle: style.label)
            colourChoice.lastItem?.representedObject = style.rawValue
        }

        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.controlSize = .small
        opacitySlider.target = self
        opacitySlider.action = #selector(restyleWireframe)
        opacitySlider.toolTip = L("wireframe.opacity")

        // Colour and opacity only appear once a wireframe is on: three
        // controls in the corner of a preview is as much as it will take.
        let controls = NSStackView(views: [modeChoice, colourChoice, opacitySlider])
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        wireframeBackdrop.addSubview(controls)

        NSLayoutConstraint.activate([
            wireframeBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            wireframeBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            controls.topAnchor.constraint(equalTo: wireframeBackdrop.topAnchor, constant: 3),
            controls.bottomAnchor.constraint(equalTo: wireframeBackdrop.bottomAnchor, constant: -3),
            controls.leadingAnchor.constraint(equalTo: wireframeBackdrop.leadingAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: wireframeBackdrop.trailingAnchor, constant: -9),
            opacitySlider.widthAnchor.constraint(equalToConstant: 70),

            // The surface sits top right, clear of the wireframe controls.
            surfaceBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            surfaceBackdrop.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            surfaceChoice.topAnchor.constraint(equalTo: surfaceBackdrop.topAnchor, constant: 3),
            surfaceChoice.bottomAnchor.constraint(equalTo: surfaceBackdrop.bottomAnchor, constant: -3),
            surfaceChoice.leadingAnchor.constraint(equalTo: surfaceBackdrop.leadingAnchor, constant: 8),
            surfaceChoice.trailingAnchor.constraint(equalTo: surfaceBackdrop.trailingAnchor, constant: -8),
        ])

        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),

            infoBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            infoBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            // The info strip gives way to the toggle rather than slide under it.
            infoBackdrop.trailingAnchor.constraint(
                lessThanOrEqualTo: wireframeBackdrop.leadingAnchor, constant: -8),

            info.topAnchor.constraint(equalTo: infoBackdrop.topAnchor, constant: 4),
            info.bottomAnchor.constraint(equalTo: infoBackdrop.bottomAnchor, constant: -4),
            info.leadingAnchor.constraint(equalTo: infoBackdrop.leadingAnchor, constant: 8),
            info.trailingAnchor.constraint(equalTo: infoBackdrop.trailingAnchor, constant: -9),
        ])
    }

    public override func layout() {
        super.layout()
        // The backdrop layer is not governed by constraints, so resize it by
        // hand — and without the implicit animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        CATransaction.commit()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackdrop()
    }

    private func updateBackdrop() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        backdrop.colors = dark
            ? [NSColor(white: 0.16, alpha: 1).cgColor, NSColor(white: 0.08, alpha: 1).cgColor]
            : [NSColor(white: 0.97, alpha: 1).cgColor, NSColor(white: 0.86, alpha: 1).cgColor]
        backdrop.startPoint = CGPoint(x: 0.5, y: 1)
        backdrop.endPoint = CGPoint(x: 0.5, y: 0)
    }

    // MARK: Content

    public func show(mesh: Mesh, filename: String?) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        isDark = dark
        let scene = SceneBuilder.scene(for: mesh, darkBackground: dark)

        sceneView.scene = scene
        sceneView.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        sceneView.isHidden = false

        // SceneKit's camera controller targets the origin by default, but it has
        // to be told again after every scene change, or the orbit pivots around
        // the previous point of view.
        sceneView.defaultCameraController.interactionMode = .orbitTurntable
        sceneView.defaultCameraController.target = SCNVector3Zero
        sceneView.defaultCameraController.inertiaEnabled = true

        pivot = scene.rootNode.childNode(withName: "pivot", recursively: false)
        startIdleRotation()

        currentMesh = mesh
        wireframeBackdrop.isHidden = false
        surfaceBackdrop.isHidden = false
        restoreSettings()
        applySurface()
        rebuildWireframe()

        var parts = [mesh.sourceFormat,
                     L("info.triangles", Self.counter.string(from: NSNumber(value: mesh.triangleCount)) ?? "\(mesh.triangleCount)"),
                     MeshDocument.dimensionsLabel(for: mesh)]
        if let filename { parts.insert(filename, at: 0) }
        infoLabel.stringValue = parts.joined(separator: "   ·   ")
        infoBackdrop.isHidden = false
    }

    public func show(error: Error, filename: String?) {
        sceneView.isHidden = true
        currentMesh = nil
        wireframeBackdrop.isHidden = true
        surfaceBackdrop.isHidden = true
        helpBackdrop.isHidden = true
        infoBackdrop.isHidden = false
        infoLabel.stringValue = (filename.map { "\($0)   ·   " } ?? "")
            + (error.localizedDescription)
        infoLabel.textColor = .systemRed
    }

    @objc private func toggleHelp() {
        helpBackdrop.isHidden.toggle()
    }

    // MARK: Settings

    private func select<T: RawRepresentable & CaseIterable & Equatable>(
        _ value: T, in popup: NSPopUpButton) where T.RawValue == String {
        popup.selectItem(at: Array(T.allCases).firstIndex(of: value) ?? 0)
    }

    private func chosen<T: RawRepresentable>(_ popup: NSPopUpButton, _ fallback: T) -> T
    where T.RawValue == String {
        (popup.selectedItem?.representedObject as? String).flatMap(T.init(rawValue:)) ?? fallback
    }

    private func restoreSettings() {
        let defaults = UserDefaults.standard
        select(defaults.string(forKey: Self.modeKey).flatMap(WireframeMode.init(rawValue:)) ?? .off,
               in: modeChoice)
        select(defaults.string(forKey: Self.colourKey).flatMap(WireframeStyle.init(rawValue:)) ?? .automatic,
               in: colourChoice)
        select(defaults.string(forKey: Self.surfaceKey).flatMap(SurfaceStyle.init(rawValue:)) ?? .light,
               in: surfaceChoice)
        // `double(forKey:)` gives 0 for an absent key, which would mean an
        // invisible wireframe on the very first preview.
        opacitySlider.doubleValue = defaults.object(forKey: Self.opacityKey) as? Double ?? 0.65
    }

    @objc private func changeWireframeMode() {
        UserDefaults.standard.set(modeChoice.selectedItem?.representedObject as? String,
                                  forKey: Self.modeKey)
        rebuildWireframe()
    }

    @objc private func restyleWireframe() {
        let defaults = UserDefaults.standard
        defaults.set(colourChoice.selectedItem?.representedObject as? String, forKey: Self.colourKey)
        defaults.set(opacitySlider.doubleValue, forKey: Self.opacityKey)
        styleWireframe()
    }

    @objc private func changeSurface() {
        UserDefaults.standard.set(surfaceChoice.selectedItem?.representedObject as? String,
                                  forKey: Self.surfaceKey)
        applySurface()
    }

    private func applySurface() {
        guard let scene = sceneView.scene else { return }
        SceneBuilder.apply(chosen(surfaceChoice, SurfaceStyle.light), to: scene)
    }

    /// Replaces the wireframe node. Finding the edges of a large mesh takes
    /// long enough to freeze a click, so it runs off the main thread and the
    /// result is discarded if the viewer has moved on.
    private func rebuildWireframe() {
        guard let mesh = currentMesh,
              let model = sceneView.scene?.rootNode
                .childNode(withName: SceneBuilder.modelName, recursively: true) else { return }

        model.childNode(withName: SceneBuilder.wireframeName, recursively: false)?
            .removeFromParentNode()

        let mode = chosen(modeChoice, WireframeMode.off)
        colourChoice.isHidden = mode == .off
        opacitySlider.isHidden = mode == .off
        guard mode != .off else { return }

        wireframeGeneration += 1
        let generation = wireframeGeneration

        guard mode == .edges else {
            attach(SceneBuilder.wireframe(for: mesh, mode: mode), to: model)
            return
        }
        Task.detached(priority: .userInitiated) {
            let edges = FeatureEdges.lines(of: mesh)
            await MainActor.run { [weak self] in
                // The node is looked up again rather than carried across: an
                // SCNNode is not Sendable, and the scene may have changed.
                guard let self, self.wireframeGeneration == generation,
                      let model = self.sceneView.scene?.rootNode
                        .childNode(withName: SceneBuilder.modelName, recursively: true) else { return }
                self.attach(SceneBuilder.wireframe(for: mesh, mode: .edges, edges: edges), to: model)
            }
        }
    }

    private func attach(_ node: SCNNode?, to model: SCNNode) {
        guard let node else { return }
        model.addChildNode(node)
        styleWireframe()
    }

    private func styleWireframe() {
        guard let geometry = sceneView.scene?.rootNode
            .childNode(withName: SceneBuilder.wireframeName, recursively: true)?.geometry else { return }
        SceneBuilder.style(geometry,
                           color: chosen(colourChoice, WireframeStyle.automatic).color(dark: isDark),
                           opacity: CGFloat(opacitySlider.doubleValue))
    }

    // MARK: Idle rotation

    private func startIdleRotation() {
        guard let pivot else { return }
        pivot.removeAction(forKey: "idle")
        let period = 60 / Self.idleTurnsPerMinute
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: period)
        pivot.runAction(.repeatForever(spin), forKey: "idle")
        sceneView.rendersContinuously = true
    }

    private func suspendIdleRotation() {
        pivot?.removeAction(forKey: "idle")
        interactionGeneration += 1
        let generation = interactionGeneration

        // The node keeps whatever orientation it reached: rotation resumes from
        // where the viewer left the part, not from the initial angle.
        Task { @MainActor [weak self] in
            // `Task.sleep(for:)` would require macOS 13; the nanosecond variant
            // has been there since concurrency landed and reads just as well.
            try? await Task.sleep(nanoseconds: UInt64(Self.resumeDelay * 1_000_000_000))
            guard let self, self.interactionGeneration == generation else { return }
            self.startIdleRotation()
        }
    }
}

/// `SCNView` handles the mouse itself to drive its camera, so events never
/// reach the parent view. We observe them on the way through without altering
/// the original behaviour.
private final class InteractiveSceneView: SCNView {
    var onInteraction: (() -> Void)?

    override func mouseDown(with event: NSEvent)    { onInteraction?(); super.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { onInteraction?(); super.rightMouseDown(with: event) }
    override func scrollWheel(with event: NSEvent)  { onInteraction?(); super.scrollWheel(with: event) }
    override func magnify(with event: NSEvent)      { onInteraction?(); super.magnify(with: event) }
    override func rotate(with event: NSEvent)       { onInteraction?(); super.rotate(with: event) }
}
