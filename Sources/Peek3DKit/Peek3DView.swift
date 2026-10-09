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
    private var pivot: SCNNode?
    private let wireframeToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let wireframeBackdrop = NSVisualEffectView()
    private let colourChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let opacitySlider = NSSlider(value: 0.65, minValue: 0.1, maxValue: 1,
                                         target: nil, action: nil)
    private var isDark = false

    /// These choices follow the viewer from one file to the next. An extension
    /// has its own defaults container, so this touches nothing else — and it
    /// cannot read the host application's settings either, which is why the
    /// controls live in the preview rather than in a preferences window.
    private static let wireframeKey = "ShowWireframe"
    private static let colourKey = "WireframeColour"
    private static let opacityKey = "WireframeOpacity"
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
        infoBackdrop.addSubview(infoLabel)

        wireframeBackdrop.translatesAutoresizingMaskIntoConstraints = false
        wireframeBackdrop.material = .hudWindow
        wireframeBackdrop.blendingMode = .withinWindow
        wireframeBackdrop.state = .active
        wireframeBackdrop.wantsLayer = true
        wireframeBackdrop.layer?.cornerRadius = 7
        wireframeBackdrop.layer?.masksToBounds = true
        wireframeBackdrop.isHidden = true
        addSubview(wireframeBackdrop)

        wireframeToggle.translatesAutoresizingMaskIntoConstraints = false
        wireframeToggle.title = L("preview.wireframe")
        wireframeToggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        wireframeToggle.font = .systemFont(ofSize: 11)
        wireframeToggle.target = self
        wireframeToggle.action = #selector(toggleWireframe)
        wireframeBackdrop.addSubview(wireframeToggle)

        NSLayoutConstraint.activate([
            wireframeBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            wireframeBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            wireframeToggle.topAnchor.constraint(equalTo: wireframeBackdrop.topAnchor, constant: 3),
            wireframeToggle.bottomAnchor.constraint(equalTo: wireframeBackdrop.bottomAnchor, constant: -3),
            wireframeToggle.leadingAnchor.constraint(equalTo: wireframeBackdrop.leadingAnchor, constant: 8),
            wireframeToggle.trailingAnchor.constraint(equalTo: wireframeBackdrop.trailingAnchor, constant: -9),
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

            infoLabel.topAnchor.constraint(equalTo: infoBackdrop.topAnchor, constant: 4),
            infoLabel.bottomAnchor.constraint(equalTo: infoBackdrop.bottomAnchor, constant: -4),
            infoLabel.leadingAnchor.constraint(equalTo: infoBackdrop.leadingAnchor, constant: 9),
            infoLabel.trailingAnchor.constraint(equalTo: infoBackdrop.trailingAnchor, constant: -9),
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

        let wire = scene.rootNode.childNode(withName: SceneBuilder.wireframeName, recursively: true)
        // Above the triangle limit no wireframe is built, and the checkbox goes
        // with it: offering a control that does nothing is worse than no control.
        wireframeBackdrop.isHidden = wire == nil
        if wire != nil {
            let defaults = UserDefaults.standard
            let on = defaults.bool(forKey: Self.wireframeKey)
            wireframeToggle.state = on ? .on : .off

            let stored = defaults.string(forKey: Self.colourKey)
            let style = stored.flatMap(WireframeStyle.init(rawValue:)) ?? .automatic
            colourChoice.selectItem(at: WireframeStyle.allCases.firstIndex(of: style) ?? 0)

            // `double(forKey:)` gives 0 for an absent key, which would mean an
            // invisible wireframe on the very first preview.
            let opacity = defaults.object(forKey: Self.opacityKey) as? Double ?? 0.65
            opacitySlider.doubleValue = opacity

            applyWireframeSettings()
        }

        var parts = [mesh.sourceFormat,
                     L("info.triangles", Self.counter.string(from: NSNumber(value: mesh.triangleCount)) ?? "\(mesh.triangleCount)"),
                     MeshDocument.dimensionsLabel(for: mesh)]
        if let filename { parts.insert(filename, at: 0) }
        infoLabel.stringValue = parts.joined(separator: "   ·   ")
        infoBackdrop.isHidden = false
    }

    public func show(error: Error, filename: String?) {
        sceneView.isHidden = true
        wireframeBackdrop.isHidden = true
        infoBackdrop.isHidden = false
        infoLabel.stringValue = (filename.map { "\($0)   ·   " } ?? "")
            + (error.localizedDescription)
        infoLabel.textColor = .systemRed
    }

    @objc private func toggleWireframe() {
        UserDefaults.standard.set(wireframeToggle.state == .on, forKey: Self.wireframeKey)
        applyWireframeSettings()
    }

    @objc private func restyleWireframe() {
        let style = colourChoice.selectedItem?.representedObject as? String
        UserDefaults.standard.set(style, forKey: Self.colourKey)
        UserDefaults.standard.set(opacitySlider.doubleValue, forKey: Self.opacityKey)
        applyWireframeSettings()
    }

    /// Pushes the three settings onto the scene and the controls at once, so
    /// there is one path to get right rather than three.
    private func applyWireframeSettings() {
        guard let wire = sceneView.scene?.rootNode
            .childNode(withName: SceneBuilder.wireframeName, recursively: true) else { return }

        let on = wireframeToggle.state == .on
        wire.isHidden = !on
        colourChoice.isHidden = !on
        opacitySlider.isHidden = !on

        let style = (colourChoice.selectedItem?.representedObject as? String)
            .flatMap(WireframeStyle.init(rawValue:)) ?? .automatic
        if let geometry = wire.geometry {
            SceneBuilder.style(geometry,
                               color: style.color(dark: isDark),
                               opacity: CGFloat(opacitySlider.doubleValue))
        }
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
