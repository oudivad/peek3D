import AppKit
import QuickLookUI

/// The Quick Look preview controller — what appears when you press space in
/// the Finder.
///
/// The system grants `preparePreviewOfFile` a limited time and kills the
/// extension past it. All reading therefore happens off the main thread, and a
/// CAD part is tessellated at "preview" fineness rather than the highest.
final class PreviewViewController: NSViewController, QLPreviewingController {

    private let preview = Peek3DView()

    override func loadView() {
        preview.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        preview.autoresizingMask = [.width, .height]
        view = preview
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let filename = url.lastPathComponent

        // Return a `Result` rather than let the error propagate: this method is
        // called by the system, where throwing means "no preview at all" rather
        // than "here is what went wrong".
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Mesh, Error> in
            do { return .success(try MeshDocument.load(url: url, quality: .preview)) }
            catch { return .failure(error) }
        }.value

        switch outcome {
        case .success(let mesh):
            preview.show(mesh: mesh, filename: filename)
        case .failure(let error):
            // Show the error instead of propagating it: a failing extension
            // leaves Quick Look on a blank, silent panel, whereas a message at
            // least says why the file will not open.
            preview.show(error: error, filename: filename)
        }
    }
}
