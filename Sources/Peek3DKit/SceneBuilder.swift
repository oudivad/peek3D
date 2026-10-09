import Foundation
import SceneKit
import simd
import AppKit

/// The colours offered for the wireframe. A list rather than the system colour
/// picker: that opens a window of its own, which is a poor fit for a preview
/// panel that comes and goes with the space bar.
public enum WireframeStyle: String, CaseIterable, Sendable {
    case automatic, black, white, grey
    case red, orange, yellow, green, cyan, blue, purple, magenta

    /// `automatic` follows the panel: dark lines on a light background, light
    /// lines on a dark one.
    public func color(dark: Bool) -> NSColor {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
            NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
        }
        switch self {
        case .automatic: return NSColor(white: dark ? 0.92 : 0.12, alpha: 1)
        case .black:     return NSColor(white: 0.05, alpha: 1)
        case .white:     return NSColor(white: 0.97, alpha: 1)
        case .grey:      return NSColor(white: 0.50, alpha: 1)
        case .red:       return rgb(0.85, 0.20, 0.20)
        case .orange:    return rgb(0.93, 0.52, 0.13)
        case .yellow:    return rgb(0.93, 0.80, 0.15)
        case .green:     return rgb(0.22, 0.70, 0.30)
        case .cyan:      return rgb(0.15, 0.72, 0.80)
        case .blue:      return rgb(0.15, 0.45, 0.90)
        case .purple:    return rgb(0.55, 0.35, 0.85)
        case .magenta:   return rgb(0.85, 0.25, 0.70)
        }
    }

    public var label: String { L("wireframe.colour.\(rawValue)") }
}

/// How much of the mesh to draw as lines.
public enum WireframeMode: String, CaseIterable, Sendable {
    case off, edges, triangles

    public var label: String { L("wireframe.mode.\(rawValue)") }
}

/// The surface the part is rendered in.
///
/// The spread is deliberate: filament colours for anyone looking at a print,
/// and three metals for anyone looking at a machined part. Metalness and
/// roughness move with the colour, since brass that shades like plastic looks
/// like neither.
public enum SurfaceStyle: String, CaseIterable, Sendable {
    case light, white, black, graphite
    case red, orange, yellow, green, teal, blue, purple, pink
    case steel, brass, copper

    var colour: NSColor {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
            NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
        }
        switch self {
        case .light:    return rgb(0.82, 0.84, 0.87)
        case .white:    return rgb(0.95, 0.95, 0.95)
        case .black:    return rgb(0.13, 0.13, 0.14)
        case .graphite: return rgb(0.30, 0.31, 0.33)
        case .red:      return rgb(0.76, 0.22, 0.20)
        case .orange:   return rgb(0.88, 0.47, 0.16)
        case .yellow:   return rgb(0.89, 0.74, 0.20)
        case .green:    return rgb(0.32, 0.60, 0.33)
        case .teal:     return rgb(0.22, 0.60, 0.60)
        case .blue:     return rgb(0.30, 0.49, 0.75)
        case .purple:   return rgb(0.50, 0.37, 0.70)
        case .pink:     return rgb(0.85, 0.47, 0.62)
        case .steel:    return rgb(0.70, 0.72, 0.75)
        case .brass:    return rgb(0.76, 0.62, 0.29)
        case .copper:   return rgb(0.72, 0.44, 0.30)
        }
    }

    var metalness: CGFloat {
        switch self {
        case .steel, .brass, .copper: return 0.85
        default: return 0.05
        }
    }

    var roughness: CGFloat {
        switch self {
        case .steel:  return 0.28
        case .brass:  return 0.32
        case .copper: return 0.34
        default:      return 0.38
        }
    }

    public var label: String { L("surface.\(rawValue)") }
}

/// Turns a `Mesh` into a SceneKit scene ready to display.
public enum SceneBuilder {

    /// Radius of the sphere every model is scaled to fit. Working at a
    /// normalized size avoids two pitfalls: camera settings that depend on the
    /// part, and float precision loss on a model expressed in microns or
    /// kilometres.
    public static let normalizedRadius: Float = 1

    /// Vertical field of view.
    static let fieldOfView: Float = 32

    /// Name of the wireframe node, so the view can find and replace it.
    public static let wireframeName = "wireframe"

    /// Name of the node holding the part itself.
    public static let modelName = "model"

    /// Slack around the bounding sphere. Framing it exactly makes the part look
    /// like it is touching the edges of the Quick Look panel.
    static let framingMargin: Float = 1.12

    public static func scene(for mesh: Mesh, darkBackground: Bool) -> SCNScene {
        let scene = SCNScene()

        let node = SCNNode(geometry: geometry(for: mesh))
        node.name = modelName
        normalize(node, mesh: mesh)

        // A pivot separate from the model node lets the part spin about its
        // centre without disturbing its scale.
        let pivot = SCNNode()
        pivot.name = "pivot"
        pivot.addChildNode(node)
        scene.rootNode.addChildNode(pivot)

        scene.rootNode.addChildNode(cameraNode())
        for light in lights() { scene.rootNode.addChildNode(light) }

        scene.background.contents = backgroundImage(dark: darkBackground)
        // Environment lighting is what makes the PBR shading convincing:
        // without it, metal surfaces look flat and dull.
        scene.lightingEnvironment.contents = environmentImage(dark: darkBackground)
        scene.lightingEnvironment.intensity = darkBackground ? 1.0 : 1.4

        return scene
    }

    // MARK: Geometry

    public static func geometry(for mesh: Mesh) -> SCNGeometry {
        // `SIMD3<Float>` occupies 16 bytes, padded to four components. Declaring
        // that stride beats repacking everything into 12-byte vectors.
        let stride = MemoryLayout<SIMD3<Float>>.stride

        let positionData = mesh.positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let normalData = mesh.normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let indexData = mesh.indices.withUnsafeBufferPointer { Data(buffer: $0) }

        let positions = SCNGeometrySource(
            data: positionData, semantic: .vertex,
            vectorCount: mesh.positions.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: stride)

        let normals = SCNGeometrySource(
            data: normalData, semantic: .normal,
            vectorCount: mesh.normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: stride)

        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles,
            primitiveCount: mesh.triangleCount,
            bytesPerIndex: MemoryLayout<UInt32>.size)

        let geometry = SCNGeometry(sources: [positions, normals], elements: [element])
        geometry.materials = [material()]
        return geometry
    }

    /// Positions alone, for the line geometry: feature edges carry no normal
    /// and the lines are drawn unlit anyway.
    static func positionSource(for mesh: Mesh) -> SCNGeometrySource {
        let stride = MemoryLayout<SIMD3<Float>>.stride
        return SCNGeometrySource(
            data: mesh.positions.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .vertex,
            vectorCount: mesh.positions.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: stride)
    }

    /// The mesh drawn as lines over the solid part, in whichever mode is asked
    /// for. Returns nil for `.off`, or when a mesh yields no edge worth drawing.
    ///
    /// SceneKit has no depth bias, so lines sharing their geometry with the
    /// surface underneath would z-fight into a stipple. Growing the copy by a
    /// fraction of a percent, about the model's own centre, lifts it clear
    /// without any visible displacement.
    ///
    /// `edges` lets the caller pass lines computed elsewhere: finding them on a
    /// million-triangle mesh takes long enough to be worth doing off the main
    /// thread, and the geometry has to be built on it.
    public static func wireframe(for mesh: Mesh,
                                 mode: WireframeMode,
                                 edges: [UInt32]? = nil) -> SCNNode? {
        let shape: SCNGeometry
        switch mode {
        case .off:
            return nil
        case .triangles:
            guard let copy = geometry(for: mesh).copy() as? SCNGeometry else { return nil }
            copy.firstMaterial?.fillMode = .lines
            shape = copy
        case .edges:
            let lines = edges ?? FeatureEdges.lines(of: mesh)
            guard lines.count >= 2 else { return nil }
            let element = SCNGeometryElement(
                data: lines.withUnsafeBufferPointer { Data(buffer: $0) },
                primitiveType: .line,
                primitiveCount: lines.count / 2,
                bytesPerIndex: MemoryLayout<UInt32>.size)
            shape = SCNGeometry(sources: [positionSource(for: mesh)], elements: [element])
        }

        let lines = SCNMaterial()
        lines.lightingModel = .constant
        lines.diffuse.contents = NSColor.black
        lines.writesToDepthBuffer = false
        lines.isDoubleSided = true
        if mode == .triangles { lines.fillMode = .lines }
        shape.materials = [lines]

        let node = SCNNode(geometry: shape)
        node.name = wireframeName
        node.renderingOrder = 10

        // Scale about the model's own centre: translate the centre to the
        // origin, grow, translate back. `pivot` would have displaced the
        // content instead of only moving the point it scales around.
        let centre = mesh.center
        let growth: CGFloat = 1.0015
        var transform = SCNMatrix4MakeTranslation(CGFloat(centre.x), CGFloat(centre.y), CGFloat(centre.z))
        transform = SCNMatrix4Scale(transform, growth, growth, growth)
        transform = SCNMatrix4Translate(transform, CGFloat(-centre.x), CGFloat(-centre.y), CGFloat(-centre.z))
        node.transform = transform
        return node
    }

    /// Applies a surface to the part already in a scene.
    public static func apply(_ surface: SurfaceStyle, to scene: SCNScene) {
        guard let material = scene.rootNode
            .childNode(withName: modelName, recursively: true)?
            .geometry?.firstMaterial else { return }
        material.diffuse.contents = surface.colour
        material.metalness.contents = surface.metalness
        material.roughness.contents = surface.roughness
    }

    public static func style(_ geometry: SCNGeometry, color: NSColor, opacity: CGFloat) {
        guard let material = geometry.firstMaterial else { return }
        material.emission.contents = color
        material.transparency = max(0.05, min(1, opacity))
    }

    public static func material() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.87, alpha: 1)
        m.metalness.contents = 0.05
        m.roughness.contents = 0.38
        // Plenty of STL files from consumer modellers have inconsistently wound
        // triangles; without this the part looks full of holes.
        m.isDoubleSided = true
        return m
    }

    /// Centres the model on the origin and scales it to the normalized radius.
    static func normalize(_ node: SCNNode, mesh: Mesh) {
        let center = mesh.center
        let radius = mesh.boundingRadius
        let scale = radius > 0 ? normalizedRadius / radius : 1

        node.position = SCNVector3(-center.x * scale, -center.y * scale, -center.z * scale)
        node.scale = SCNVector3(scale, scale, scale)
    }

    // MARK: Camera and lights

    static func cameraNode() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(fieldOfView)
        camera.zNear = 0.05
        camera.zFar = 200
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false

        let node = SCNNode()
        node.name = "camera"
        node.camera = camera
        // Closest distance at which a sphere of `normalizedRadius` still fits
        // the field of view, whatever the part.
        let halfAngle = fieldOfView * .pi / 360
        let distance = normalizedRadius / sin(halfAngle) * framingMargin

        // A slightly raised three-quarter view: the angle that reads a part's
        // volume best when you are seeing it for the first time.
        let direction = simd_normalize(SIMD3<Float>(0.62, 0.46, 0.84))
        node.position = SCNVector3(direction.x * distance,
                                   direction.y * distance,
                                   direction.z * distance)
        node.look(at: SCNVector3Zero)
        return node
    }

    static func lights() -> [SCNNode] {
        func directional(_ intensity: CGFloat, _ x: Float, _ y: Float, _ z: Float,
                         temperature: CGFloat) -> SCNNode {
            let light = SCNLight()
            light.type = .directional
            light.intensity = intensity
            light.temperature = temperature
            let node = SCNNode()
            node.light = light
            node.position = SCNVector3(x, y, z)
            node.look(at: SCNVector3Zero)
            return node
        }

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 180
        let ambientNode = SCNNode()
        ambientNode.light = ambient

        return [
            // Key light, slightly cool, which draws the edges.
            directional(700, -4, 6, 5, temperature: 6600),
            // Opposing fill, warmer and weaker: it keeps faces from going fully
            // black without flattening the relief.
            directional(260, 5, -2, -4, temperature: 4800),
            ambientNode,
        ]
    }

    // MARK: Procedural backgrounds

    /// A soft vertical gradient. A flat colour renders flat, and shipping a
    /// background image would mean duplicating it in every bundle.
    static func backgroundImage(dark: Bool) -> NSImage {
        gradient(size: CGSize(width: 2, height: 512),
                 top: dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.97, alpha: 1),
                 bottom: dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.82, alpha: 1))
    }

    /// A simplified spherical environment: bright sky above, dark ground below.
    /// It is the least that makes PBR produce a believable reflection.
    static func environmentImage(dark: Bool) -> NSImage {
        gradient(size: CGSize(width: 4, height: 256),
                 top: dark ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 1.0, alpha: 1),
                 bottom: dark ? NSColor(white: 0.05, alpha: 1) : NSColor(white: 0.25, alpha: 1))
    }

    private static func gradient(size: CGSize, top: NSColor, bottom: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(starting: bottom, ending: top)?
            .draw(in: NSRect(origin: .zero, size: size), angle: 90)
        image.unlockFocus()
        return image
    }
}
