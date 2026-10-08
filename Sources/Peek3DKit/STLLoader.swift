import Foundation
import simd

/// STL reader, covering both flavours of the format: binary (80-byte header
/// then 50 bytes per facet) and ASCII (`solid` / `facet normal`).
public enum STLLoader {

    public static func load(data: Data) throws -> Mesh {
        if let corners = try binaryCorners(data) {
            return try MeshBuilder.build(corners: corners, format: "Binary STL")
        }
        return try MeshBuilder.build(corners: try asciiCorners(data), format: "ASCII STL")
    }

    // MARK: Binary

    /// Returns `nil` unless the file size matches the binary layout exactly.
    /// That is the only reliable test, because a binary STL may perfectly well
    /// begin with the bytes "solid".
    private static func binaryCorners(_ data: Data) throws -> [SIMD3<Float>]? {
        guard data.count >= 84 else { return nil }
        let declared = data.withUnsafeBytes { raw -> UInt32 in
            raw.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian
        }
        let count = Int(declared)
        guard count > 0, 84 + count * 50 == data.count else { return nil }

        var corners = [SIMD3<Float>](repeating: .zero, count: count * 3)
        data.withUnsafeBytes { raw in
            for f in 0..<count {
                // Skip the 12 bytes of stated normal: it is often wrong or
                // zero, so we recompute it from the geometry instead.
                var offset = 84 + f * 50 + 12
                for v in 0..<3 {
                    let x = Float(bitPattern: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian)
                    let y = Float(bitPattern: raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).littleEndian)
                    let z = Float(bitPattern: raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self).littleEndian)
                    corners[f * 3 + v] = SIMD3<Float>(x, y, z)
                    offset += 12
                }
            }
        }
        return corners
    }

    // MARK: ASCII

    /// Sweeps the bytes for `vertex x y z` lines without building intermediate
    /// strings: on a 100 MB file the difference runs to tens of seconds.
    private static func asciiCorners(_ data: Data) throws -> [SIMD3<Float>] {
        var corners = [SIMD3<Float>]()
        corners.reserveCapacity(data.count / 48)

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                throw MeshError.empty
            }
            let n = raw.count
            var i = 0

            while i < n {
                // Move to the next "vertex" keyword.
                guard let v = find(base, from: i, to: n, token: "vertex") else { break }
                i = v + 6
                var components = SIMD3<Float>.zero
                for c in 0..<3 {
                    guard let value = readFloat(base, at: &i, to: n) else {
                        throw MeshError.malformed("missing coordinate after \"vertex\"")
                    }
                    components[c] = value
                }
                corners.append(components)
            }
        }

        guard !corners.isEmpty else { throw MeshError.empty }
        guard corners.count % 3 == 0 else {
            throw MeshError.malformed("vertex count is not a multiple of 3 (\(corners.count))")
        }
        return corners
    }

    private static func find(_ p: UnsafePointer<CChar>, from: Int, to: Int, token: String) -> Int? {
        let t = Array(token.utf8).map { CChar(bitPattern: $0) }
        let last = to - t.count
        guard last >= from else { return nil }
        var i = from
        while i <= last {
            if p[i] == t[0] {
                var k = 1
                while k < t.count, p[i + k] == t[k] { k += 1 }
                if k == t.count { return i }
            }
            i += 1
        }
        return nil
    }

    private static func readFloat(_ p: UnsafePointer<CChar>, at i: inout Int, to n: Int) -> Float? {
        while i < n, isSpace(p[i]) { i += 1 }
        guard i < n else { return nil }
        var end: UnsafeMutablePointer<CChar>?
        let value = strtof(p + i, &end)
        guard let end, UnsafePointer(end) != p + i else { return nil }
        i = UnsafePointer(end) - p
        return value
    }

    @inline(__always)
    private static func isSpace(_ c: CChar) -> Bool {
        c == 32 || c == 9 || c == 10 || c == 13
    }
}
