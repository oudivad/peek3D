import AppKit
import Foundation

/// Builds Resources/AppIcon.icns.
///
/// Two possible sources. An image — the usual case, when the icon was drawn
/// elsewhere — whose rounded plate must be cut out and its surroundings made
/// transparent. Or a 3D model, rendered by the application's own engine, which
/// saves committing an opaque binary with no source beside it.
@main
enum MakeIcon {

    /// Sizes iconutil requires for a complete .icns.
    static let sizes: [(name: String, points: Int, scale: Int)] = [
        ("icon_16x16",      16, 1), ("icon_16x16@2x",     16, 2),
        ("icon_32x32",      32, 1), ("icon_32x32@2x",     32, 2),
        ("icon_128x128",   128, 1), ("icon_128x128@2x",  128, 2),
        ("icon_256x256",   256, 1), ("icon_256x256@2x",  256, 2),
        ("icon_512x512",   512, 1), ("icon_512x512@2x",  512, 2),
    ]

    /// macOS icon geometry since Big Sur: the rounded plate does not fill the
    /// square, it leaves a transparent margin on every side.
    static let artworkRatio: CGFloat = 824.0 / 1024.0

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            FileHandle.standardError.write(Data("usage: make-icon <image|model> <output.icns>\n".utf8))
            exit(2)
        }
        let source = URL(fileURLWithPath: arguments[1])
        let output = URL(fileURLWithPath: arguments[2])

        let artwork: NSImage
        switch source.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "tiff", "heic":
            guard let loaded = NSImage(contentsOf: source) else {
                FileHandle.standardError.write(Data("unreadable image: \(source.path)\n".utf8))
                exit(1)
            }
            artwork = try trimmed(loaded)
        default:
            artwork = try renderModel(at: source)
        }

        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("Peek3D-\(UUID().uuidString).iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        for size in sizes {
            let pixels = size.points * size.scale
            guard let png = compose(artwork: artwork, pixels: pixels) else {
                FileHandle.standardError.write(Data("could not compose at \(pixels) px\n".utf8))
                exit(1)
            }
            try png.write(to: iconset.appendingPathComponent("\(size.name).png"))
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        try iconutil.run()
        iconutil.waitUntilExit()
        guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

        print("✓ \(output.path)")
    }

    // MARK: Cutting out

    /// Isolates the rounded plate from an image that holds it on some background.
    ///
    /// An icon drawn elsewhere usually arrives as a screenshot: opaque
    /// background, approximate framing. One could clip a rounded rectangle over
    /// it, but macOS plates follow a continuous curve that a circular arc does
    /// not match, so the mask bites into the corners and clips the artwork.
    ///
    /// We work the other way round: start from the edges of the image and erase
    /// outwards through everything dark, stopping at the bright ring of the
    /// outline. The original silhouette is preserved exactly, whatever its
    /// curvature, and the subject — however dark — stays intact because that
    /// ring encloses it.
    static func trimmed(_ image: NSImage) throws -> NSImage {
        guard let source = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else {
            throw Failure("image illisible")
        }
        let width = source.pixelsWide, height = source.pixelsHigh

        // Redraw into a known format: the original representation may be planar,
        // indexed or alpha-less, in which case reading the bytes directly would
        // assume a layout that is not there.
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
            let pixels = canvas.bitmapData else {
            throw Failure("could not allocate the image buffer")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        /// Threshold separating the background from the outline's bright ring.
        let threshold = 0.78 * 255
        func isDark(_ offset: Int) -> Bool {
            let r = Double(pixels[offset]), g = Double(pixels[offset + 1]), b = Double(pixels[offset + 2])
            return 0.299 * r + 0.587 * g + 0.114 * b < threshold
        }

        // Breadth-first flood from all four edges.
        var queue = [Int]()
        var erased = [Bool](repeating: false, count: width * height)

        func enqueue(_ x: Int, _ y: Int) {
            let index = y * width + x
            guard !erased[index], isDark(index * 4) else { return }
            erased[index] = true
            queue.append(index)
        }

        for x in 0..<width { enqueue(x, 0); enqueue(x, height - 1) }
        for y in 0..<height { enqueue(0, y); enqueue(width - 1, y) }

        var head = 0
        while head < queue.count {
            let index = queue[head]; head += 1
            let x = index % width, y = index / width
            if x > 0 { enqueue(x - 1, y) }
            if x < width - 1 { enqueue(x + 1, y) }
            if y > 0 { enqueue(x, y - 1) }
            if y < height - 1 { enqueue(x, y + 1) }
        }

        for index in 0..<(width * height) where erased[index] {
            pixels[index * 4 + 3] = 0
        }

        // Crop tight to whatever remains visible.
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { throw Failure("the image was erased entirely") }

        let box = NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        let result = NSImage(size: box.size)
        result.lockFocus()
        canvas.draw(in: NSRect(origin: .zero, size: box.size),
                    // `draw(from:)` measures its ordinates from the bottom.
                    from: NSRect(x: box.minX, y: CGFloat(height) - box.maxY,
                                 width: box.width, height: box.height),
                    operation: .copy, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        result.unlockFocus()
        return result
    }

    // MARK: Composition

    /// Places the plate on the transparent square macOS expects.
    static func compose(artwork: NSImage, pixels: Int) -> Data? {
        let side = CGFloat(pixels)
        let span = (side * artworkRatio).rounded()
        let plate = NSRect(x: ((side - span) / 2).rounded(),
                           y: ((side - span) / 2).rounded(),
                           width: span, height: span)

        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        NSGraphicsContext.current?.imageInterpolation = .high

        // No mask: cutting out already gave the image its exact silhouette, and
        // clipping it again could only damage it.
        artwork.draw(in: plate, from: .zero, operation: .sourceOver, fraction: 1)

        NSGraphicsContext.restoreGraphicsState()
        return canvas.representation(using: .png, properties: [:])
    }

    // MARK: Rendering from a 3D model

    static func renderModel(at url: URL) throws -> NSImage {
        let mesh = try MeshDocument.load(url: url, quality: .detailed)
        guard let image = Thumbnailer.image(for: mesh,
                                            size: CGSize(width: 1024, height: 1024),
                                            scale: 1) else {
            throw Failure("could not render the model")
        }
        return image
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
