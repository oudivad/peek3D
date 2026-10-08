import Foundation
import simd
import OCCTBridge

/// STEP / IGES reader. Unlike the mesh formats, these files describe exact
/// surfaces — planes, cylinders, NURBS — so there are no triangles to read:
/// they have to be computed. That is OpenCASCADE's job, behind `OCCTBridge`.
public enum CADLoader {

    /// Tessellation fineness. Compute cost varies by an order of magnitude
    /// between the two extremes.
    public enum Quality: Int32 {
        case thumbnail = 0
        case preview   = 1
        case detailed  = 2
    }

    /// Vertex ceiling. Past this point the display gains nothing visible while
    /// memory and compute keep climbing — and the system kills a Quick Look
    /// extension that dawdles.
    public static let defaultBudget = 4_000_000

    public static func load(url: URL,
                            quality: Quality = .preview,
                            budget: Int = defaultBudget) throws -> Mesh {
        var result = P3DStepMesh()
        let code = url.path.withCString { path in
            p3d_cad_load(path, quality.rawValue, size_t(budget), &result)
        }
        defer { p3d_mesh_free(&result) }

        guard code == 0 else {
            let detail = result.error.map { String(cString: $0) } ?? "unknown cause"
            throw MeshError.malformed(detail)
        }
        guard let raw = result.corners, result.cornerCount > 0 else {
            throw MeshError.empty
        }

        let count = Int(result.cornerCount)
        var corners = [SIMD3<Float>](repeating: .zero, count: count)
        raw.withMemoryRebound(to: Float.self, capacity: count * 3) { floats in
            for i in 0..<count {
                corners[i] = SIMD3<Float>(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
            }
        }

        let format = url.pathExtension.lowercased().hasPrefix("ig") ? "IGES" : "STEP"
        var mesh = try MeshBuilder.build(corners: corners, format: format)
        mesh.sourceFormat = L("format.cad.faces", format, Int(result.faceCount))
        mesh.unit = "mm"   // OpenCASCADE always normalizes geometry to millimetres
        return mesh
    }

    public static var openCascadeVersion: String {
        String(cString: p3d_occt_version())
    }
}
