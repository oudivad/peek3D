import Foundation
import simd

/// Extracts the edges that describe a shape, as opposed to every edge of its
/// triangulation.
///
/// Drawing all the triangles of a dense mesh gives a black smear that hides the
/// part rather than revealing it. What is worth seeing is where the surface
/// actually turns: the boundary between two faces that meet at an angle, and
/// the open borders of a surface. On a tessellated cylinder that leaves the two
/// rims and the seam; on a machined part it leaves what a drawing would show.
public enum FeatureEdges {

    /// Angle between adjacent faces past which their shared edge is kept. The
    /// same reasoning as the crease angle used for normals, a little tighter:
    /// an edge can be worth drawing before it is worth breaking the shading.
    public static let defaultAngle: Float = 25 * .pi / 180

    /// Returns index pairs into `mesh.positions`, ready for a `.line` element.
    public static func lines(of mesh: Mesh, angle: Float = defaultAngle) -> [UInt32] {
        guard mesh.triangleCount > 0 else { return [] }

        // Vertices were split by crease when the mesh was built, so two
        // triangles sharing an edge in space may not share an index. Work in
        // terms of one representative index per position, and the seams close.
        var representative = [PositionKey: UInt32](minimumCapacity: mesh.positions.count)
        var proxy = [UInt32](repeating: 0, count: mesh.positions.count)
        for (index, position) in mesh.positions.enumerated() {
            let key = PositionKey(position)
            if let existing = representative[key] {
                proxy[index] = existing
            } else {
                representative[key] = UInt32(index)
                proxy[index] = UInt32(index)
            }
        }

        struct Incidence {
            var first: SIMD3<Float>
            var second: SIMD3<Float>?
        }
        // Keyed on the two representative indices packed into one integer:
        // a dictionary of structs would cost several times the memory, and on a
        // million triangles that is the difference between working and not.
        var edges = [UInt64: Incidence](minimumCapacity: mesh.triangleCount * 2)

        for triangle in 0..<mesh.triangleCount {
            let i = Int(mesh.indices[triangle * 3])
            let j = Int(mesh.indices[triangle * 3 + 1])
            let k = Int(mesh.indices[triangle * 3 + 2])
            let normal = safeNormalize(cross(mesh.positions[j] - mesh.positions[i],
                                             mesh.positions[k] - mesh.positions[i]))

            for (a, b) in [(proxy[i], proxy[j]), (proxy[j], proxy[k]), (proxy[k], proxy[i])] {
                guard a != b else { continue }   // degenerate triangle
                let key = a < b ? UInt64(a) << 32 | UInt64(b) : UInt64(b) << 32 | UInt64(a)
                if edges[key] == nil {
                    edges[key] = Incidence(first: normal, second: nil)
                } else if edges[key]!.second == nil {
                    edges[key]!.second = normal
                }
                // A third face on one edge means a non-manifold mesh; the first
                // two are enough to judge whether the edge turns.
            }
        }

        let threshold = cos(angle)
        var lines = [UInt32]()
        lines.reserveCapacity(edges.count / 4)

        for (key, incidence) in edges {
            let keep: Bool
            if let second = incidence.second {
                keep = dot(incidence.first, second) < threshold
            } else {
                // A single face means an open border — always worth drawing.
                keep = true
            }
            guard keep else { continue }
            lines.append(UInt32(key >> 32))
            lines.append(UInt32(key & 0xFFFF_FFFF))
        }
        return lines
    }
}
