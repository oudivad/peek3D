import Foundation

/// A small text reader that works straight off the bytes. ASCII 3D files are
/// often large, and going through `String`/`split` costs an order of magnitude
/// in both time and memory.
struct ByteScanner {
    let base: UnsafePointer<CChar>
    let count: Int
    var pos: Int = 0

    init(_ raw: UnsafeRawBufferPointer) {
        base = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
        count = raw.count
    }

    var isAtEnd: Bool { pos >= count }

    @inline(__always) static func isSpace(_ c: CChar) -> Bool { c == 32 || c == 9 || c == 13 }
    @inline(__always) static func isNewline(_ c: CChar) -> Bool { c == 10 }

    /// Advances to the next meaningful character on the current line.
    @inline(__always) mutating func skipSpaces() {
        while pos < count, Self.isSpace(base[pos]) { pos += 1 }
    }

    @inline(__always) mutating func skipToNextLine() {
        while pos < count, !Self.isNewline(base[pos]) { pos += 1 }
        if pos < count { pos += 1 }
    }

    /// Whitespace-delimited word, returned without copying.
    @inline(__always) mutating func token() -> UnsafeBufferPointer<CChar>? {
        skipSpaces()
        guard pos < count, !Self.isNewline(base[pos]) else { return nil }
        let start = pos
        while pos < count, !Self.isSpace(base[pos]), !Self.isNewline(base[pos]) { pos += 1 }
        return UnsafeBufferPointer(start: base + start, count: pos - start)
    }

    @inline(__always) mutating func float() -> Float? {
        skipSpaces()
        guard pos < count, !Self.isNewline(base[pos]) else { return nil }
        var end: UnsafeMutablePointer<CChar>?
        let value = strtof(base + pos, &end)
        guard let end, UnsafePointer(end) != base + pos else { return nil }
        pos = UnsafePointer(end) - base
        return value
    }

    @inline(__always) mutating func int() -> Int? {
        skipSpaces()
        guard pos < count, !Self.isNewline(base[pos]) else { return nil }
        var end: UnsafeMutablePointer<CChar>?
        let value = strtol(base + pos, &end, 10)
        guard let end, UnsafePointer(end) != base + pos else { return nil }
        pos = UnsafePointer(end) - base
        return value
    }
}

extension UnsafeBufferPointer where Element == CChar {
    @inline(__always) func matches(_ s: String) -> Bool {
        let t = Array(s.utf8)
        guard count == t.count else { return false }
        for i in 0..<count where UInt8(bitPattern: self[i]) != t[i] { return false }
        return true
    }
    var string: String {
        String(decoding: self.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
