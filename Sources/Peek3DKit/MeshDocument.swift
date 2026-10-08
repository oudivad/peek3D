import Foundation
import UniformTypeIdentifiers

/// The single entry point: maps a file extension to its reader.
public enum MeshDocument {

    /// Recognized extensions. The list in the code and the lists in the
    /// `Info.plist` files must agree; keeping them in one place here is what
    /// makes that checkable.
    public static let meshExtensions = ["stl", "obj", "ply", "3mf"]
    public static let cadExtensions  = ["step", "stp", "iges", "igs"]
    public static var allExtensions: [String] { meshExtensions + cadExtensions }

    public static func canLoad(_ url: URL) -> Bool {
        allExtensions.contains(url.pathExtension.lowercased())
    }

    public static func load(url: URL, quality: CADLoader.Quality = .preview) throws -> Mesh {
        let ext = url.pathExtension.lowercased()

        // CAD formats read the file themselves: OpenCASCADE wants a path, and
        // these files are too large to be loaded twice.
        if cadExtensions.contains(ext) {
            return try CADLoader.load(url: url, quality: quality)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw MeshError.unreadable(error.localizedDescription)
        }

        switch ext {
        case "stl": return try STLLoader.load(data: data)
        case "obj": return try OBJLoader.load(data: data)
        case "ply": return try PLYLoader.load(data: data)
        case "3mf": return try ThreeMFLoader.load(data: data)
        default:    throw MeshError.unsupported(".\(ext)")
        }
    }

    /// Human-readable dimensions, shown under the preview.
    public static func dimensionsLabel(for mesh: Mesh) -> String {
        let s = mesh.size
        let unit = mesh.unit.map { " \($0)" } ?? ""
        func fmt(_ v: Float) -> String {
            // Past 100, a tenth of a millimetre tells the reader nothing.
            v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        }
        return "\(fmt(s.x)) × \(fmt(s.y)) × \(fmt(s.z))\(unit)"
    }
}
