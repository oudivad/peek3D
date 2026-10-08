import Foundation
import simd

/// Stanford PLY reader: ASCII and binary, little- and big-endian. The header
/// freely describes the order and type of every property, so it has to be read
/// before the body can be interpreted at all.
public enum PLYLoader {

    enum Scalar: String {
        case int8, uint8, int16, uint16, int32, uint32, float32, float64

        var size: Int {
            switch self {
            case .int8, .uint8:   return 1
            case .int16, .uint16: return 2
            case .int32, .uint32, .float32: return 4
            case .float64: return 8
            }
        }

        /// The format's historic type names coexist with the explicit ones.
        static func parse(_ s: String) -> Scalar? {
            switch s {
            case "char", "int8":     return .int8
            case "uchar", "uint8":   return .uint8
            case "short", "int16":   return .int16
            case "ushort", "uint16": return .uint16
            case "int", "int32":     return .int32
            case "uint", "uint32":   return .uint32
            case "float", "float32": return .float32
            case "double", "float64": return .float64
            default: return Scalar(rawValue: s)
            }
        }
    }

    struct Property {
        let name: String
        let type: Scalar
        /// Non-nil for a list property: the type of the count that precedes it.
        let countType: Scalar?
    }

    struct Element {
        let name: String
        let count: Int
        var properties: [Property]
    }

    enum Encoding { case ascii, binaryLittle, binaryBig }

    public static func load(data: Data) throws -> Mesh {
        let (elements, encoding, bodyOffset) = try parseHeader(data)

        let vertexProps = elements.first { $0.name == "vertex" }
        guard let vertexProps, vertexProps.count > 0 else {
            throw MeshError.malformed("no \"vertex\" element in the PLY header")
        }

        var vertices = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var faces = [[Int]]()

        switch encoding {
        case .ascii:
            try readASCII(data, from: bodyOffset, elements: elements,
                          vertices: &vertices, normals: &normals, faces: &faces)
        case .binaryLittle, .binaryBig:
            try readBinary(data, from: bodyOffset, elements: elements,
                           bigEndian: encoding == .binaryBig,
                           vertices: &vertices, normals: &normals, faces: &faces)
        }

        guard !faces.isEmpty else { throw MeshError.empty }
        let hasNormals = normals.count == vertices.count

        var corners = [SIMD3<Float>]()
        var cornerNormals = [SIMD3<Float>]()
        for face in faces where face.count >= 3 {
            for k in 1..<(face.count - 1) {
                for idx in [face[0], face[k], face[k + 1]] {
                    guard idx >= 0, idx < vertices.count else { continue }
                    corners.append(vertices[idx])
                    if hasNormals { cornerNormals.append(normals[idx]) }
                }
            }
        }
        guard corners.count >= 3, corners.count % 3 == 0 else { throw MeshError.empty }

        return hasNormals && cornerNormals.count == corners.count
            ? try MeshBuilder.build(corners: corners, cornerNormals: cornerNormals, format: "PLY")
            : try MeshBuilder.build(corners: corners, format: "PLY")
    }

    // MARK: Header

    private static func parseHeader(_ data: Data) throws -> ([Element], Encoding, Int) {
        // The header is always ASCII and ends with "end_header".
        let probe = data.prefix(64 * 1024)
        guard let text = String(data: probe, encoding: .isoLatin1),
              text.hasPrefix("ply") else {
            throw MeshError.malformed("missing PLY signature")
        }
        guard let endRange = text.range(of: "end_header") else {
            throw MeshError.malformed("\"end_header\" not found")
        }
        // The binary body starts after the newline following end_header.
        var bodyOffset = text.distance(from: text.startIndex, to: endRange.upperBound)
        while bodyOffset < data.count, data[data.startIndex + bodyOffset] != 0x0A { bodyOffset += 1 }
        bodyOffset += 1

        var encoding: Encoding?
        var elements = [Element]()

        for rawLine in text[text.startIndex..<endRange.lowerBound].split(separator: "\n") {
            let fields = rawLine.split(whereSeparator: { $0 == " " || $0 == "\r" || $0 == "\t" }).map(String.init)
            guard let keyword = fields.first else { continue }

            switch keyword {
            case "format":
                guard fields.count >= 2 else { break }
                switch fields[1] {
                case "ascii":                encoding = .ascii
                case "binary_little_endian": encoding = .binaryLittle
                case "binary_big_endian":    encoding = .binaryBig
                default: throw MeshError.unsupported("PLY encoding \"\(fields[1])\"")
                }
            case "element":
                guard fields.count >= 3, let n = Int(fields[2]) else { break }
                elements.append(Element(name: fields[1], count: n, properties: []))
            case "property":
                guard !elements.isEmpty, fields.count >= 3 else { break }
                if fields[1] == "list" {
                    guard fields.count >= 5,
                          let countType = Scalar.parse(fields[2]),
                          let itemType = Scalar.parse(fields[3]) else { break }
                    elements[elements.count - 1].properties.append(
                        Property(name: fields[4], type: itemType, countType: countType))
                } else {
                    guard let t = Scalar.parse(fields[1]) else { break }
                    elements[elements.count - 1].properties.append(
                        Property(name: fields[2], type: t, countType: nil))
                }
            default:
                break
            }
        }

        guard let encoding else { throw MeshError.malformed("missing \"format\" line") }
        return (elements, encoding, bodyOffset)
    }

    // MARK: ASCII body

    private static func readASCII(_ data: Data, from offset: Int, elements: [Element],
                                  vertices: inout [SIMD3<Float>],
                                  normals: inout [SIMD3<Float>],
                                  faces: inout [[Int]]) throws {
        var v = [SIMD3<Float>](), n = [SIMD3<Float>](), f = [[Int]]()
        data.withUnsafeBytes { raw in
            var s = ByteScanner(UnsafeRawBufferPointer(rebasing: raw[offset...]))
            for element in elements {
                for _ in 0..<element.count {
                    var p = SIMD3<Float>.zero, nrm = SIMD3<Float>.zero
                    var hasN = false
                    var indices = [Int]()
                    for prop in element.properties {
                        if let _ = prop.countType {
                            let k = s.int() ?? 0
                            indices.reserveCapacity(k)
                            for _ in 0..<max(0, k) { indices.append(s.int() ?? 0) }
                        } else {
                            let value = s.float() ?? 0
                            switch prop.name {
                            case "x": p.x = value
                            case "y": p.y = value
                            case "z": p.z = value
                            case "nx": nrm.x = value; hasN = true
                            case "ny": nrm.y = value; hasN = true
                            case "nz": nrm.z = value; hasN = true
                            default: break
                            }
                        }
                    }
                    if element.name == "vertex" {
                        v.append(p)
                        if hasN { n.append(nrm) }
                    } else if element.name == "face", !indices.isEmpty {
                        f.append(indices)
                    }
                    s.skipToNextLine()
                }
            }
        }
        vertices = v; normals = n; faces = f
    }

    // MARK: Binary body

    private static func readBinary(_ data: Data, from offset: Int, elements: [Element],
                                   bigEndian: Bool,
                                   vertices: inout [SIMD3<Float>],
                                   normals: inout [SIMD3<Float>],
                                   faces: inout [[Int]]) throws {
        var v = [SIMD3<Float>](), n = [SIMD3<Float>](), f = [[Int]]()
        var overflow = false

        data.withUnsafeBytes { raw in
            var cursor = offset

            func read(_ type: Scalar) -> Double {
                guard cursor + type.size <= raw.count else { overflow = true; return 0 }
                defer { cursor += type.size }
                func u16() -> UInt16 { let x = raw.loadUnaligned(fromByteOffset: cursor, as: UInt16.self); return bigEndian ? x.bigEndian : x.littleEndian }
                func u32() -> UInt32 { let x = raw.loadUnaligned(fromByteOffset: cursor, as: UInt32.self); return bigEndian ? x.bigEndian : x.littleEndian }
                func u64() -> UInt64 { let x = raw.loadUnaligned(fromByteOffset: cursor, as: UInt64.self); return bigEndian ? x.bigEndian : x.littleEndian }
                switch type {
                case .int8:    return Double(raw.loadUnaligned(fromByteOffset: cursor, as: Int8.self))
                case .uint8:   return Double(raw.loadUnaligned(fromByteOffset: cursor, as: UInt8.self))
                case .int16:   return Double(Int16(bitPattern: u16()))
                case .uint16:  return Double(u16())
                case .int32:   return Double(Int32(bitPattern: u32()))
                case .uint32:  return Double(u32())
                case .float32: return Double(Float(bitPattern: u32()))
                case .float64: return Double(bitPattern: u64())
                }
            }

            outer: for element in elements {
                v.reserveCapacity(element.name == "vertex" ? element.count : 0)
                for _ in 0..<element.count {
                    var p = SIMD3<Float>.zero, nrm = SIMD3<Float>.zero
                    var hasN = false
                    var indices = [Int]()
                    for prop in element.properties {
                        if let countType = prop.countType {
                            let k = Int(read(countType))
                            guard k >= 0, k < 1 << 20 else { overflow = true; break outer }
                            indices.reserveCapacity(k)
                            for _ in 0..<k { indices.append(Int(read(prop.type))) }
                        } else {
                            let value = Float(read(prop.type))
                            switch prop.name {
                            case "x": p.x = value
                            case "y": p.y = value
                            case "z": p.z = value
                            case "nx": nrm.x = value; hasN = true
                            case "ny": nrm.y = value; hasN = true
                            case "nz": nrm.z = value; hasN = true
                            default: break
                            }
                        }
                    }
                    if overflow { break outer }
                    if element.name == "vertex" {
                        v.append(p)
                        if hasN { n.append(nrm) }
                    } else if element.name == "face", !indices.isEmpty {
                        f.append(indices)
                    }
                }
            }
        }

        if overflow && f.isEmpty {
            throw MeshError.malformed("truncated PLY body")
        }
        vertices = v; normals = n; faces = f
    }
}
