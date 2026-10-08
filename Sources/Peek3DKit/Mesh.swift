import Foundation
import simd

/// An indexed triangle mesh, ready to be uploaded to the GPU.
public struct Mesh: Sendable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var indices: [UInt32]

    /// Shown in the preview's info strip.
    public var sourceFormat: String
    /// Unit of the coordinates when the format states one ("mm", "in"…).
    /// STL carries none, so its dimensions stay unitless.
    public var unit: String?
    public var triangleCount: Int { indices.count / 3 }

    public init(positions: [SIMD3<Float>],
                normals: [SIMD3<Float>],
                indices: [UInt32],
                sourceFormat: String,
                unit: String? = nil) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.sourceFormat = sourceFormat
        self.unit = unit
    }

    public var isEmpty: Bool { indices.isEmpty || positions.isEmpty }

    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard var lo = positions.first else { return (.zero, .zero) }
        var hi = lo
        for p in positions {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return (lo, hi)
    }

    public var size: SIMD3<Float> {
        let b = bounds
        return b.max - b.min
    }

    /// Radius of the sphere around `center` that encloses the whole model.
    /// Framing follows this rather than the bounding box: a long flat part has
    /// to push the camera back as far as a cube of the same diagonal.
    public var boundingRadius: Float {
        let c = center
        var r2: Float = 0
        for p in positions { r2 = max(r2, simd_length_squared(p - c)) }
        return sqrt(r2)
    }

    public var center: SIMD3<Float> {
        let b = bounds
        return (b.min + b.max) * 0.5
    }
}

public enum MeshError: LocalizedError {
    case unreadable(String)
    case malformed(String)
    case unsupported(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):  return L("error.unreadable", detail)
        case .malformed(let detail):   return L("error.malformed", detail)
        case .unsupported(let detail): return L("error.unsupported", detail)
        case .empty:                   return L("error.empty")
        }
    }
}

// MARK: - Building from a triangle soup

public enum MeshBuilder {

    /// Angle past which an edge counts as sharp and normals stop being averaged
    /// across it. 35° keeps the flat faces of a machined part crisp while still
    /// smoothing faceted curved surfaces.
    public static let defaultCreaseAngle: Float = 35 * .pi / 180

    /// Builds an indexed mesh from unshared vertices, three per triangle.
    ///
    /// Identical positions are welded, then grouped by orientation: one point in
    /// space can yield several vertices when the faces meeting there sit more
    /// than `creaseAngle` apart.
    public static func build(corners: [SIMD3<Float>],
                             format: String,
                             creaseAngle: Float = defaultCreaseAngle) throws -> Mesh {
        guard !corners.isEmpty, corners.count % 3 == 0 else {
            throw MeshError.empty
        }
        let faceCount = corners.count / 3
        let creaseCos = cos(creaseAngle)

        // Geometric normal of each face, left unnormalized: its length is twice
        // the area, which weights the average by face size for free.
        var faceNormals = [SIMD3<Float>](repeating: .zero, count: faceCount)
        for f in 0..<faceCount {
            let a = corners[f * 3], b = corners[f * 3 + 1], c = corners[f * 3 + 2]
            faceNormals[f] = cross(b - a, c - a)
        }

        // Group corners by exact position.
        var groups = [PositionKey: [Int]]()
        groups.reserveCapacity(corners.count / 4)
        for i in 0..<corners.count {
            groups[PositionKey(corners[i]), default: []].append(i)
        }

        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var indices = [UInt32](repeating: 0, count: corners.count)
        positions.reserveCapacity(groups.count)
        normals.reserveCapacity(groups.count)

        // Reused across groups to avoid allocating in the inner loop.
        var clusterSums = [SIMD3<Float>]()
        var clusterSlots = [Int]()

        for (_, cornerIndices) in groups {
            clusterSums.removeAll(keepingCapacity: true)
            clusterSlots.removeAll(keepingCapacity: true)

            for corner in cornerIndices {
                let n = faceNormals[corner / 3]
                let unit = safeNormalize(n)

                // Look for an open cluster whose average orientation still sits
                // within `creaseAngle` of this face.
                var match = -1
                for (c, sum) in clusterSums.enumerated()
                where dot(safeNormalize(sum), unit) >= creaseCos {
                    match = c
                    break
                }

                if match >= 0 {
                    clusterSums[match] += n
                    indices[corner] = UInt32(clusterSlots[match])
                } else {
                    clusterSums.append(n)
                    clusterSlots.append(positions.count)
                    indices[corner] = UInt32(positions.count)
                    positions.append(corners[corner])
                    normals.append(.zero)   // filled in after the loop
                }
            }

            for (c, slot) in clusterSlots.enumerated() {
                normals[slot] = safeNormalize(clusterSums[c])
            }
        }

        return Mesh(positions: positions,
                    normals: normals,
                    indices: indices,
                    sourceFormat: format)
    }
}

extension MeshBuilder {

    /// Variant for formats that already carry normals (OBJ, PLY).
    ///
    /// Honouring the author's intent beats recomputing: welding on the
    /// position-and-normal pair preserves deliberately smoothed surfaces and
    /// deliberately hard edges alike.
    public static func build(corners: [SIMD3<Float>],
                             cornerNormals: [SIMD3<Float>],
                             format: String) throws -> Mesh {
        precondition(corners.count == cornerNormals.count)
        guard !corners.isEmpty, corners.count % 3 == 0 else { throw MeshError.empty }

        var slots = [VertexKey: UInt32]()
        slots.reserveCapacity(corners.count / 4)
        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var indices = [UInt32]()
        indices.reserveCapacity(corners.count)

        for i in 0..<corners.count {
            let n = safeNormalize(cornerNormals[i])
            let key = VertexKey(position: PositionKey(corners[i]), normal: PositionKey(n))
            if let existing = slots[key] {
                indices.append(existing)
            } else {
                let slot = UInt32(positions.count)
                slots[key] = slot
                indices.append(slot)
                positions.append(corners[i])
                normals.append(n)
            }
        }
        return Mesh(positions: positions, normals: normals, indices: indices, sourceFormat: format)
    }
}

struct VertexKey: Hashable {
    let position: PositionKey
    let normal: PositionKey
}

/// Normalizes, falling back to an arbitrary up vector for degenerate triangles
/// of zero area — common in carelessly exported STL files.
@inline(__always)
func safeNormalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = length(v)
    return len > 1e-20 ? v / len : SIMD3<Float>(0, 1, 0)
}

/// Hashes a position by its bit pattern: two vertices from the same file that
/// are meant to coincide carry identical bytes.
struct PositionKey: Hashable {
    let x: UInt32, y: UInt32, z: UInt32
    init(_ p: SIMD3<Float>) {
        // -0.0 and +0.0 must hash alike.
        x = (p.x == 0 ? 0 : p.x).bitPattern
        y = (p.y == 0 ? 0 : p.y).bitPattern
        z = (p.z == 0 ? 0 : p.z).bitPattern
    }
}
