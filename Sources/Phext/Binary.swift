// Binary.swift — canonical binary scrolls, ported 1:1 from
// libphext-rs 0.6.0 (src/binary.rs).
//
// A binary scroll is exactly:
//   phext-binary:1:base64\n<base64 body>
// RFC 4648 base64, standard alphabet, padding required, no wrapping.
// Foundation's Data base64 is strict in the same sense rs's base64 crate
// is (it rejects non-alphabet bytes and bad padding), which the tests pin.

import Foundation

public enum PhextBinary {
    public static let binaryScrollHeader = "phext-binary:1:base64"
    static let binaryScrollPrefix = "phext-binary:1:base64\n"

    public static func isBinaryScroll(_ scroll: String) -> Bool {
        scroll.hasPrefix(binaryScrollPrefix)
    }

    public static func encodeScroll(_ payload: [UInt8]) -> String {
        binaryScrollPrefix + Data(payload).base64EncodedString()
    }

    /// Decodes a binary scroll, or returns nil when the scroll is not a
    /// binary scroll or its body is not strict base64.
    public static func decodeScroll(_ scroll: String) -> [UInt8]? {
        guard scroll.hasPrefix(binaryScrollPrefix) else { return nil }
        let body = String(scroll.dropFirst(binaryScrollPrefix.count))
        // Foundation tolerates some inputs rs rejects (it ignores unknown
        // characters only under an explicit option; by default it returns
        // nil for non-alphabet bytes). It also accepts a missing final
        // padding in some cases, so enforce the canonical shape first:
        // length a multiple of 4, alphabet + at most two trailing '='.
        guard isStrictBase64(body), let data = Data(base64Encoded: body) else { return nil }
        return [UInt8](data)
    }

    static func isStrictBase64(_ body: String) -> Bool {
        let bytes = [UInt8](body.utf8)
        if bytes.isEmpty { return true }
        guard bytes.count % 4 == 0 else { return false }
        var padding = 0
        for (i, b) in bytes.enumerated() {
            let isAlphabet = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
                || (b >= 0x30 && b <= 0x39) || b == 0x2B || b == 0x2F
            if b == 0x3D { // '='
                padding += 1
                guard i >= bytes.count - 2, padding <= 2 else { return false }
            } else {
                guard padding == 0, isAlphabet else { return false }
            }
        }
        return true
    }

    public static func insertBinary(_ input: String, _ location: Coordinate, _ payload: [UInt8]) -> String {
        Phext.insert(input, location, encodeScroll(payload))
    }

    public static func replaceBinary(_ input: String, _ location: Coordinate, _ payload: [UInt8]) -> String {
        Phext.replace(input, location, encodeScroll(payload))
    }

    /// The bytes held at `target`: a well-formed binary scroll decodes to
    /// its payload; any other scroll yields its own UTF-8 bytes (empty
    /// when unoccupied). Total: never fails, never loses content.
    public static func fetchBinary(_ input: String, _ target: Coordinate) -> [UInt8] {
        let scroll = Phext.fetch(input, target)
        if let bytes = decodeScroll(scroll) {
            return bytes
        }
        return [UInt8](scroll.utf8)
    }

    /// The stored form of an incoming scroll update, per the ingestion
    /// rule: valid UTF-8 stays text; anything else becomes a binary
    /// scroll holding the base64 of the exact observed bytes, verbatim.
    static func storedForm(_ payload: [UInt8]) -> String {
        if isValidUTF8(payload) {
            return String(decoding: payload, as: UTF8.self)
        }
        return encodeScroll(payload)
    }

    static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        // Foundation's String(validatingAs:) reports validity without
        // substitution (Swift 5.9+ stdlib).
        String(validating: bytes, as: UTF8.self) != nil
    }

    public static func insertBytes(_ input: String, _ location: Coordinate, _ payload: [UInt8]) -> String {
        Phext.insert(input, location, storedForm(payload))
    }

    public static func replaceBytes(_ input: String, _ location: Coordinate, _ payload: [UInt8]) -> String {
        Phext.replace(input, location, storedForm(payload))
    }

    /// The byte-level twin of `Phext.phokenize`, with identical
    /// segmentation; scroll bodies are returned uninterpreted.
    public static func phokenizeBytes(_ input: [UInt8]) -> [(Coordinate, [UInt8])] {
        var result: [(Coordinate, [UInt8])] = []
        let max = input.count
        var coord = Coordinate()
        var pi = 0
        while true {
            let start = coord
            var begin = start
            var textStart: Int? = nil
            var textEnd = max
            while pi < max {
                let byte = input[pi]
                if Phext.isDimensionBreak(byte) {
                    Phext.applyBreak(&coord, byte)
                    if textStart != nil {
                        textEnd = pi
                        pi += 1
                        break
                    }
                } else if textStart == nil {
                    textStart = pi
                    begin = coord
                }
                pi += 1
            }
            let scroll: [UInt8]
            if let first = textStart {
                scroll = [UInt8](input[first..<textEnd])
            } else {
                scroll = []
            }
            result.append((begin, scroll))
            if pi >= max { break }
        }
        return result
    }

    /// Ingests an externally supplied phext byte stream: valid UTF-8
    /// scrolls pass through verbatim; any scroll whose bytes are not
    /// valid UTF-8 is stored as a binary scroll holding the base64 of
    /// the exact observed bytes. Never rejects. The result is the
    /// canonical serialization (implode of explode).
    public static func ingest(_ bytes: [UInt8]) -> String {
        let parts = phokenizeBytes(bytes)
        var map: [Coordinate: String] = [:]
        for (coord, raw) in parts {
            if isValidUTF8(raw) {
                map[coord] = String(decoding: raw, as: UTF8.self)
            } else {
                map[coord] = encodeScroll(raw)
            }
        }
        return Phext.implode(map)
    }
}
