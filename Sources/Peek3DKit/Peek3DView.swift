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
        infoBackdrop.addSubview(infoLabel)

        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),

            infoBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            infoBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

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

        var parts = [mesh.sourceFormat,
                     L("info.triangles", Self.counter.string(from: NSNumber(value: mesh.triangleCount)) ?? "\(mesh.triangleCount)"),
                     MeshDocument.dimensionsLabel(for: mesh)]
        if let filename { parts.insert(filename, at: 0) }
        infoLabel.stringValue = parts.joined(separator: "   ·   ")
        infoBackdrop.isHidden = false
    }

    public func show(error: Error, filename: String?) {
        sceneView.isHidden = true
        infoBackdrop.isHidden = false
        infoLabel.stringValue = (filename.map { "\($0)   ·   " } ?? "")
            + (error.localizedDescription)
        infoLabel.textColor = .systemRed
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
