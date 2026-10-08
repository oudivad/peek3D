import AppKit
import QuickLookThumbnailing
import os

/// Thumbnail provider: replaces the Finder's generic icon with a render of the
/// part.
///
/// The constraints are tighter than for the preview — the Finder asks for
/// dozens at once while scrolling — hence the coarse tessellation of CAD
/// parts.
final class ThumbnailProvider: QLThumbnailProvider {

    /// The Finder never shows why a thumbnail failed: with no trace, "no
    /// thumbnail" is indistinguishable from "no extension installed".
    /// `log show --predicate 'subsystem == "io.github.oudivad.Peek3D"'` reveals it.
    private static let log = Logger(subsystem: "io.github.oudivad.Peek3D", category: "thumbnail")

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let mesh = try MeshDocument.load(url: request.fileURL, quality: .thumbnail)

            let reply = QLThumbnailReply(contextSize: request.maximumSize) { context in
                // `contextSize` is given in points, but the context handed over
                // here is sized in pixels with no scale transform: drawing into
                // the nominal rectangle would fill only a fraction of the
                // thumbnail on a Retina display. Going through the context's own
                // matrix tells the truth in either case.
                let device = CGRect(x: 0, y: 0, width: context.width, height: context.height)
                let bounds = device.applying(context.userSpaceToDeviceSpaceTransform.inverted())

                return Thumbnailer.draw(mesh: mesh, in: context, bounds: bounds)
            }
            handler(reply, nil)
        } catch {
            // With no reply the Finder keeps the generic document icon, which
            // is exactly the fallback we want.
            Self.log.error("""
                thumbnail declined for \(request.fileURL.lastPathComponent, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            handler(nil, error)
        }
    }
}
