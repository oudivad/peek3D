import Foundation
import SceneKit
import Metal
import AppKit

/// Offscreen rendering, for Finder thumbnails.
///
/// This goes through `SCNRenderer` rather than an `SCNView`: it needs neither a
/// window nor an event loop, which is essential inside a thumbnail extension,
/// since that runs with no interface at all.
public enum Thumbnailer {

    /// Past this size the Finder resamples anyway.
    public static let maximumSide: CGFloat = 1024

    public static func image(for mesh: Mesh,
                             size: CGSize,
                             scale: CGFloat = 2) -> NSImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        // The background stays transparent: a thumbnail has to sit as well on
        // the Finder's light grid as on its dark one.
        let scene = SceneBuilder.scene(for: mesh, darkBackground: false)
        scene.background.contents = NSColor.clear

        guard let camera = scene.rootNode.childNode(withName: "camera", recursively: false) else {
            return nil
        }

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = false

        let pixels = CGSize(width: min(size.width * scale, maximumSide),
                            height: min(size.height * scale, maximumSide))
        let snapshot = renderer.snapshot(atTime: 0,
                                         with: pixels,
                                         antialiasingMode: .multisampling4X)

        // `snapshot` returns an image sized in pixels; restating it in points
        // is what makes the Finder draw it sharply on a Retina display.
        let result = NSImage(size: size)
        result.addRepresentation({
            let rep = NSBitmapImageRep(data: snapshot.tiffRepresentation ?? Data())
            rep?.size = size
            return rep
        }() ?? NSBitmapImageRep())
        return result.representations.isEmpty ? snapshot : result
    }

    /// Variant for the thumbnail extension: draws straight into the graphics
    /// context the system hands over, at the true size that context reports.
    public static func draw(mesh: Mesh, in context: CGContext, bounds: CGRect) -> Bool {
        // Render at the requested aspect ratio: the Finder may ask for a
        // thumbnail that is not square, and stretching shows.
        let pixels = CGSize(width: CGFloat(context.width), height: CGFloat(context.height))
        guard pixels.width > 0, pixels.height > 0,
              let image = image(for: mesh, size: pixels, scale: 1),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        context.draw(cg, in: bounds)
        return true
    }
}
