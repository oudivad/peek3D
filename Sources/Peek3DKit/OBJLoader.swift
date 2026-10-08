import Foundation
import simd

/// Wavefront OBJ reader. Only geometry is kept: materials (`.mtl`) and textures
/// are beside the point for a quick preview, and their side files are
/// unreachable from a sandboxed Quick Look extension anyway.
public enum OBJLoader {

    public static func load(data: Data) throws -> Mesh {
        var vertices = [SIMD3<Float>]()
        var sourceNormals = [SIMD3<Float>]()
        var corners = [SIMD3<Float>]()
        var cornerNormals = [SIMD3<Float>]()
        var sawNormals = true

        // Reused for every face so fan triangulation allocates nothing.
        var faceV = [Int]()
        var faceN = [Int]()

        data.withUnsafeBytes { raw in
            var s = ByteScanner(raw)
            while !s.isAtEnd {
                guard let kind = s.token() else { s.skipToNextLine(); continue }

                if kind.matches("v") {
                    let x = s.float() ?? 0, y = s.float() ?? 0, z = s.float() ?? 0
                    vertices.append(SIMD3(x, y, z))
                } else if kind.matches("vn") {
                    let x = s.float() ?? 0, y = s.float() ?? 0, z = s.float() ?? 0
                    sourceNormals.append(SIMD3(x, y, z))
                } else if kind.matches("f") {
                    faceV.removeAll(keepingCapacity: true)
                    faceN.removeAll(keepingCapacity: true)
                    while let t = s.token() {
                        let (vi, ni) = parseFaceRef(t)
                        guard let vi else { continue }
                        faceV.append(resolve(vi, count: vertices.count))
                        faceN.append(ni.map { resolve($0, count: sourceNormals.count) } ?? -1)
                    }
                    guard faceV.count >= 3 else { s.skipToNextLine(); continue }

                    // Fan triangulation: correct for convex polygons, which is
                    // very nearly all of what OBJ files contain.
                    for k in 1..<(faceV.count - 1) {
                        for idx in [0, k, k + 1] {
                            let vi = faceV[idx]
                            corners.append(vi >= 0 && vi < vertices.count ? vertices[vi] : .zero)
                            let ni = faceN[idx]
                            if ni >= 0 && ni < sourceNormals.count {
                                cornerNormals.append(sourceNormals[ni])
                            } else {
                                sawNormals = false
                                cornerNormals.append(.zero)
                            }
                        }
                    }
                }
                s.skipToNextLine()
            }
        }

        guard !corners.isEmpty else { throw MeshError.empty }
        // One face missing a normal means recomputing all of them: mixing
        // supplied and derived normals leaves visible seams.
        return sawNormals
            ? try MeshBuilder.build(corners: corners, cornerNormals: cornerNormals, format: "OBJ")
            : try MeshBuilder.build(corners: corners, format: "OBJ")
    }

    /// Decodes `v`, `v/vt`, `v//vn` or `v/vt/vn`.
    private static func parseFaceRef(_ t: UnsafeBufferPointer<CChar>) -> (Int?, Int?) {
        var fields = [Int?](repeating: nil, count: 3)
        var field = 0, digits = 0, value = 0, negative = false
        for i in 0...t.count {
            let c: CChar = i < t.count ? t[i] : 47   // virtual '/' to close the last field
            if c == 45 && digits == 0 {
                negative = true
            } else if c >= 48 && c <= 57 {
                value = value * 10 + Int(c - 48); digits += 1
            } else if c == 47 {
                if digits > 0, field < 3 { fields[field] = negative ? -value : value }
                field += 1; digits = 0; value = 0; negative = false
                if field > 2 { break }
            }
        }
        return (fields[0], fields[2])
    }

    /// OBJ indices start at 1; negative ones count back from the end.
    @inline(__always)
    private static func resolve(_ i: Int, count: Int) -> Int {
        i > 0 ? i - 1 : count + i
    }
}
