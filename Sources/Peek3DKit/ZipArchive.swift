import Foundation
import Compression

/// A minimal ZIP reader, which is all 3MF needs: producers of the format only
/// ever use the "stored" and "deflate" methods.
///
/// Pulling in a third-party library would mean embedding it in every extension;
/// `Compression`, which ships with the system, is enough.
struct ZipArchive {
    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    init(data: Data) throws {
        self.data = data
        guard let eocd = Self.findEndOfCentralDirectory(data) else {
            throw MeshError.malformed("ZIP archive: end of central directory not found")
        }
        let entryCount = Int(data.u16(eocd + 10))
        var offset = Int(data.u32(eocd + 16))

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, data.u32(offset) == 0x0201_4b50 else { break }
            let nameLength    = Int(data.u16(offset + 28))
            let extraLength   = Int(data.u16(offset + 30))
            let commentLength = Int(data.u16(offset + 32))
            let compressed    = data.u32(offset + 20)
            let uncompressed  = data.u32(offset + 24)

            guard compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF else {
                throw MeshError.unsupported("ZIP64 archive")
            }
            let start = data.startIndex + offset + 46
            let name = String(decoding: data[start..<(start + nameLength)], as: UTF8.self)
            entries[name] = Entry(name: name,
                                  method: data.u16(offset + 10),
                                  compressedSize: Int(compressed),
                                  uncompressedSize: Int(uncompressed),
                                  localHeaderOffset: Int(data.u32(offset + 42)))
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    func contents(of name: String) throws -> Data {
        guard let entry = entries[name] else {
            throw MeshError.malformed("entry \"\(name)\" is not in the archive")
        }
        // The local header restates the name and extra lengths, which may differ
        // from the central directory's; the local one is authoritative here.
        let local = entry.localHeaderOffset
        guard local + 30 <= data.count, data.u32(local) == 0x0403_4b50 else {
            throw MeshError.malformed("corrupt local header for \"\(name)\"")
        }
        let start = local + 30 + Int(data.u16(local + 26)) + Int(data.u16(local + 28))
        let end = start + entry.compressedSize
        guard end <= data.count else { throw MeshError.malformed("truncated data for \"\(name)\"") }
        let payload = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))

        switch entry.method {
        case 0:
            return payload
        case 8:
            return try Self.inflate(payload, expecting: entry.uncompressedSize)
        default:
            throw MeshError.unsupported("ZIP compression method \(entry.method)")
        }
    }

    /// Apple's `COMPRESSION_ZLIB` means the raw DEFLATE stream, which is exactly
    /// what a ZIP stores — no zlib wrapper.
    private static func inflate(_ payload: Data, expecting size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            payload.withUnsafeBytes { src -> Int in
                compression_decode_buffer(
                    dst.baseAddress!.assumingMemoryBound(to: UInt8.self), size,
                    src.baseAddress!.assumingMemoryBound(to: UInt8.self), payload.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else {
            throw MeshError.malformed("incomplete inflate (\(written)/\(size) bytes)")
        }
        return output
    }

    /// The central directory ends with a variable-length comment, so we scan
    /// backwards from the end looking for the signature.
    private static func findEndOfCentralDirectory(_ data: Data) -> Int? {
        let maxComment = 65_535 + 22
        let lowerBound = max(0, data.count - maxComment)
        var i = data.count - 22
        while i >= lowerBound {
            if data.u32(i) == 0x0605_4b50 { return i }
            i -= 1
        }
        return nil
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian }
    }
    func u32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }
}
