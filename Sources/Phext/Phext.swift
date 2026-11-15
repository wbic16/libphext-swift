// Phext.swift — the core phext buffer library, ported 1:1 from
// libphext-rs 0.6.0 (src/phext.rs). Semantics mirror rs exactly; where rs
// works on &str this port works on String, walking its UTF-8 bytes (every
// phext break is an ASCII byte below 0x20, and UTF-8 multi-byte sequences
// never contain bytes below 0x80, so byte offsets are always character
// boundaries — the same argument rs makes).

import CLzma
import Foundation

public enum Phext {
    // MARK: - Constants (rs phext constants)

    public static let coordinateMinimum: UInt64 = 1
    public static let libraryBreak: Character = "\u{01}"
    public static let chainBreak: Character = "\u{02}"
    public static let chainClose: Character = "\u{03}"
    public static let moreCowbell: Character = "\u{07}"
    public static let lineBreak: Character = "\u{0A}"
    public static let scrollBreak: Character = "\u{17}"
    public static let sectionBreak: Character = "\u{18}"
    public static let chapterBreak: Character = "\u{19}"
    public static let bookBreak: Character = "\u{1A}"
    public static let volumeBreak: Character = "\u{1C}"
    public static let collectionBreak: Character = "\u{1D}"
    public static let seriesBreak: Character = "\u{1E}"
    public static let shelfBreak: Character = "\u{1F}"

    public static let libraryBreakU8: UInt8 = 0x01
    public static let chainBreakU8: UInt8 = 0x02
    public static let chainCloseU8: UInt8 = 0x03
    public static let moreCowbellU8: UInt8 = 0x07
    public static let lineBreakU8: UInt8 = 0x0A
    public static let scrollBreakU8: UInt8 = 0x17
    public static let sectionBreakU8: UInt8 = 0x18
    public static let chapterBreakU8: UInt8 = 0x19
    public static let bookBreakU8: UInt8 = 0x1A
    public static let volumeBreakU8: UInt8 = 0x1C
    public static let collectionBreakU8: UInt8 = 0x1D
    public static let seriesBreakU8: UInt8 = 0x1E
    public static let shelfBreakU8: UInt8 = 0x1F

    public static let addressMicroBreak: UInt8 = 0x2E // '.'
    public static let addressMacroBreak: UInt8 = 0x2F // '/'
    public static let addressMacroAlt: UInt8 = 0x3B   // ';'

    public static let version = "0.6.0"

    // MARK: - Helpers mirroring rs internals

    /// Manual equivalent of Rust `str::split(char)`: empty segments and a
    /// trailing empty tail are preserved.
    public static func splitOn(_ s: String, _ delim: Character) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in s {
            if ch == delim {
                out.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        out.append(current)
        return out
    }

    static func isDimensionBreak(_ byte: UInt8) -> Bool {
        byte == scrollBreakU8 || byte == sectionBreakU8 || byte == chapterBreakU8
            || byte == bookBreakU8 || byte == volumeBreakU8 || byte == collectionBreakU8
            || byte == seriesBreakU8 || byte == shelfBreakU8 || byte == libraryBreakU8
    }

    static func applyBreak(_ location: inout Coordinate, _ byte: UInt8) {
        if byte == scrollBreakU8 { location.scrollBreak() }
        if byte == sectionBreakU8 { location.sectionBreak() }
        if byte == chapterBreakU8 { location.chapterBreak() }
        if byte == bookBreakU8 { location.bookBreak() }
        if byte == volumeBreakU8 { location.volumeBreak() }
        if byte == collectionBreakU8 { location.collectionBreak() }
        if byte == seriesBreakU8 { location.seriesBreak() }
        if byte == shelfBreakU8 { location.shelfBreak() }
        if byte == libraryBreakU8 { location.libraryBreak() }
    }

    public static func isPhextBreak(_ byte: UInt8) -> Bool {
        byte == lineBreakU8 || isDimensionBreak(byte)
    }

    public static func defaultCoordinate() -> Coordinate { Coordinate() }

    /// Lenient address translation, mirroring rs `to_coordinate`: scans
    /// digits and delimiters, assigning components in order; malformed
    /// input yields whatever was accumulated (starting from the default).
    public static func toCoordinate(_ address: String) -> Coordinate {
        var result = Coordinate()
        var index: UInt8 = 0
        var value: UInt64 = 0
        for byte in address.utf8 {
            if byte == addressMicroBreak || byte == addressMacroBreak || byte == addressMacroAlt {
                switch index {
                case 1: result.z.library = value; index += 1
                case 2: result.z.shelf = value; index += 1
                case 3: result.z.series = value; index += 1
                case 4: result.y.collection = value; index += 1
                case 5: result.y.volume = value; index += 1
                case 6: result.y.book = value; index += 1
                case 7: result.x.chapter = value; index += 1
                case 8: result.x.section = value; index += 1
                default: break
                }
                value = 0
            }
            if byte >= 0x30 && byte <= 0x39 {
                let multiplied = value.multipliedReportingOverflow(by: 10)
                let added = multiplied.partialValue.addingReportingOverflow(UInt64(byte - 0x30))
                value = (multiplied.overflow || added.overflow) ? UInt64.max : added.partialValue
                if index == 0 { index = 1 }
            }
        }
        if index > 0 {
            result.x.scroll = value
        }
        return result
    }

    public static func checkForCowbell(_ input: String) -> Bool {
        input.utf8.contains(moreCowbellU8)
    }

    // MARK: - Subspace walking (rs get_subspace_coordinates)

    /// Returns (start, end, best) — see the rs documentation: when the
    /// document reaches `target`, start..end is that scroll's text and
    /// best is target; otherwise start == end is where the scroll would
    /// go and best is the coordinate in effect there.
    public static func getSubspaceCoordinates(_ subspace: [UInt8], _ target: Coordinate) -> (Int, Int, Coordinate) {
        var walker = Coordinate()
        var best = Coordinate()
        var found: Int? = nil
        let max = subspace.count
        var position = 0
        var moved = true

        while true {
            if moved && found == nil {
                if walker == target {
                    found = position
                    best = walker
                } else if walker < target {
                    best = walker
                } else {
                    return (position, position, best)
                }
                moved = false
            }
            if position == max { break }

            let next = subspace[position]
            if isDimensionBreak(next) {
                applyBreak(&walker, next)
                moved = true
                if walker > target {
                    if let start = found {
                        return (start, position, best)
                    }
                    return (position, position, best)
                }
                if found == position {
                    found = position + 1
                }
            }
            position += 1
        }

        if let start = found {
            return (start, max, best)
        }
        return (max, max, best)
    }

    // MARK: - Core operations

    public static func fetch(_ input: String, _ target: Coordinate) -> String {
        let bytes = [UInt8](input.utf8)
        let (start, end, _) = getSubspaceCoordinates(bytes, target)
        if end > start {
            return String(decoding: bytes[start..<end], as: UTF8.self)
        }
        return ""
    }

    private static func fixupBreaks(from subspaceCoordinate: Coordinate, to location: Coordinate) -> [UInt8] {
        var fixup: [UInt8] = []
        var coord = subspaceCoordinate
        while coord.z.library < location.z.library { fixup.append(libraryBreakU8); coord.libraryBreak() }
        while coord.z.shelf < location.z.shelf { fixup.append(shelfBreakU8); coord.shelfBreak() }
        while coord.z.series < location.z.series { fixup.append(seriesBreakU8); coord.seriesBreak() }
        while coord.y.collection < location.y.collection { fixup.append(collectionBreakU8); coord.collectionBreak() }
        while coord.y.volume < location.y.volume { fixup.append(volumeBreakU8); coord.volumeBreak() }
        while coord.y.book < location.y.book { fixup.append(bookBreakU8); coord.bookBreak() }
        while coord.x.chapter < location.x.chapter { fixup.append(chapterBreakU8); coord.chapterBreak() }
        while coord.x.section < location.x.section { fixup.append(sectionBreakU8); coord.sectionBreak() }
        while coord.x.scroll < location.x.scroll { fixup.append(scrollBreakU8); coord.scrollBreak() }
        return fixup
    }

    public static func replace(_ input: String, _ location: Coordinate, _ scroll: String) -> String {
        let bytes = [UInt8](input.utf8)
        let (start, rawEnd, best) = getSubspaceCoordinates(bytes, location)
        let end = min(rawEnd, bytes.count)
        let fixup = fixupBreaks(from: best, to: location)
        var temp: [UInt8] = []
        temp.append(contentsOf: bytes[..<start])
        temp.append(contentsOf: fixup)
        temp.append(contentsOf: scroll.utf8)
        temp.append(contentsOf: bytes[end...])
        // rs unwraps String::from_utf8 here; inputs are valid phext text.
        return String(decoding: temp, as: UTF8.self)
    }

    public static func insert(_ input: String, _ location: Coordinate, _ scroll: String) -> String {
        let bytes = [UInt8](input.utf8)
        let (_, end, best) = getSubspaceCoordinates(bytes, location)
        let fixup = fixupBreaks(from: best, to: location)
        var temp: [UInt8] = []
        temp.append(contentsOf: bytes[..<end])
        temp.append(contentsOf: fixup)
        temp.append(contentsOf: scroll.utf8)
        temp.append(contentsOf: bytes[end...])
        return String(decoding: temp, as: UTF8.self)
    }

    public static func remove(_ input: String, _ location: Coordinate) -> String {
        normalize(replace(input, location, ""))
    }

    public static func rangeReplace(_ input: String, _ location: PhextRange, _ scroll: String) -> String {
        let bytes = [UInt8](input.utf8)
        let (start, _, _) = getSubspaceCoordinates(bytes, location.start)
        let (_, rawEnd, _) = getSubspaceCoordinates(bytes, location.end)
        let end = min(rawEnd, bytes.count)
        var temp: [UInt8] = []
        temp.append(contentsOf: bytes[..<start])
        temp.append(contentsOf: scroll.utf8)
        temp.append(contentsOf: bytes[end...])
        return String(decoding: temp, as: UTF8.self)
    }

    // MARK: - phokenize / dephokenize

    public static func phokenize(_ input: String) -> [PositionedScroll] {
        let bytes = [UInt8](input.utf8)
        let max = bytes.count
        var result: [PositionedScroll] = []
        var coord = Coordinate()
        var pi = 0
        while true {
            let start = coord
            var begin = start
            var textStart: Int? = nil
            var textEnd = max
            while pi < max {
                let byte = bytes[pi]
                if isDimensionBreak(byte) {
                    applyBreak(&coord, byte)
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
            let scroll: String
            if let first = textStart {
                scroll = String(decoding: bytes[first..<textEnd], as: UTF8.self)
            } else {
                scroll = ""
            }
            result.append(PositionedScroll(coord: begin, scroll: scroll))
            if pi >= max { break }
        }
        return result
    }

    static func appendScroll(_ output: inout String, _ token: PositionedScroll, _ coordIn: Coordinate) {
        var coord = coordIn
        while coord < token.coord {
            if coord.z.library < token.coord.z.library { output.append(libraryBreak); coord.libraryBreak(); continue }
            if coord.z.shelf < token.coord.z.shelf { output.append(shelfBreak); coord.shelfBreak(); continue }
            if coord.z.series < token.coord.z.series { output.append(seriesBreak); coord.seriesBreak(); continue }
            if coord.y.collection < token.coord.y.collection { output.append(collectionBreak); coord.collectionBreak(); continue }
            if coord.y.volume < token.coord.y.volume { output.append(volumeBreak); coord.volumeBreak(); continue }
            if coord.y.book < token.coord.y.book { output.append(bookBreak); coord.bookBreak(); continue }
            if coord.x.chapter < token.coord.x.chapter { output.append(chapterBreak); coord.chapterBreak(); continue }
            if coord.x.section < token.coord.x.section { output.append(sectionBreak); coord.sectionBreak(); continue }
            if coord.x.scroll < token.coord.x.scroll { output.append(scrollBreak); coord.scrollBreak(); continue }
        }
        output += token.scroll
    }

    public static func dephokenize(_ tokens: inout [PositionedScroll]) -> String {
        var result = ""
        var coord = Coordinate()
        for ps in tokens {
            if !ps.scroll.isEmpty {
                appendScroll(&result, ps, coord)
            }
            coord = ps.coord
        }
        return result
    }

    public static func explode(_ input: String) -> [Coordinate: String] {
        var hash: [Coordinate: String] = [:]
        for row in phokenize(input) {
            hash[row.coord] = row.scroll
        }
        return hash
    }

    public static func implode(_ map: [Coordinate: String]) -> String {
        var vec = map.map { PositionedScroll(coord: $0.key, scroll: $0.value) }
        vec.sort()
        return dephokenize(&vec)
    }

    public static func normalize(_ input: String) -> String {
        var arr = phokenize(input)
        return dephokenize(&arr)
    }

    // MARK: - next_scroll

    public static func nextScroll(_ input: String, _ start: Coordinate) -> (PositionedScroll, Coordinate, String) {
        var location = start
        let p = [UInt8](input.utf8)
        var output: [UInt8] = []
        var pi = 0
        var begin = start
        let pmax = p.count
        while pi < pmax {
            var dimensionBreak = false
            if p[pi] == scrollBreakU8 { location.scrollBreak(); dimensionBreak = true }
            if p[pi] == sectionBreakU8 { location.sectionBreak(); dimensionBreak = true }
            if p[pi] == chapterBreakU8 { location.chapterBreak(); dimensionBreak = true }
            if p[pi] == bookBreakU8 { location.bookBreak(); dimensionBreak = true }
            if p[pi] == volumeBreakU8 { location.volumeBreak(); dimensionBreak = true }
            if p[pi] == collectionBreakU8 { location.collectionBreak(); dimensionBreak = true }
            if p[pi] == seriesBreakU8 { location.seriesBreak(); dimensionBreak = true }
            if p[pi] == shelfBreakU8 { location.shelfBreak(); dimensionBreak = true }
            if p[pi] == libraryBreakU8 { location.libraryBreak(); dimensionBreak = true }

            if dimensionBreak {
                if !output.isEmpty {
                    pi += 1
                    break
                }
            } else {
                begin = location
                output.append(p[pi])
            }
            pi += 1
        }
        let remaining = pi < p.count ? [UInt8](p[pi...]) : []
        let outScroll = PositionedScroll(coord: begin, scroll: String(decoding: output, as: UTF8.self))
        return (outScroll, location, String(decoding: remaining, as: UTF8.self))
    }

    // MARK: - merge / subtract

    public static func merge(_ left: String, _ right: String) -> String {
        let tl = phokenize(left)
        let tr = phokenize(right)
        var tli = 0
        var tri = 0
        var result = ""
        var coord = Coordinate()
        while true {
            let haveLeft = tli < tl.count
            let haveRight = tri < tr.count
            let pickLeft = haveLeft && (!haveRight || tl[tli].coord <= tr[tri].coord)
            let pickRight = haveRight && (!haveLeft || tr[tri].coord <= tl[tli].coord)
            if pickLeft {
                appendScroll(&result, tl[tli], coord)
                coord = tl[tli].coord
                tli += 1
            }
            if pickRight {
                appendScroll(&result, tr[tri], coord)
                coord = tr[tri].coord
                tri += 1
            }
            if !pickLeft && !pickRight { break }
        }
        return result
    }

    public static func subtract(_ left: String, _ right: String) -> String {
        let pl = phokenize(left)
        let pr = phokenize(right)
        var result = ""
        var pri = 0
        var coord = Coordinate()
        for token in pl {
            if token.scroll.isEmpty { continue }
            while pri < pr.count && pr[pri].coord < token.coord {
                pri += 1
            }
            let masked = pri < pr.count && pr[pri].coord == token.coord && !pr[pri].scroll.isEmpty
            if !masked {
                appendScroll(&result, token, coord)
                coord = token.coord
            }
        }
        return result
    }

    // MARK: - expand / contract

    public static func expand(_ input: String) -> String {
        var buffer = [UInt8](input.utf8)
        for p in buffer.indices {
            switch buffer[p] {
            case lineBreakU8: buffer[p] = scrollBreakU8
            case scrollBreakU8: buffer[p] = sectionBreakU8
            case sectionBreakU8: buffer[p] = chapterBreakU8
            case chapterBreakU8: buffer[p] = bookBreakU8
            case bookBreakU8: buffer[p] = volumeBreakU8
            case volumeBreakU8: buffer[p] = collectionBreakU8
            case collectionBreakU8: buffer[p] = seriesBreakU8
            case seriesBreakU8: buffer[p] = shelfBreakU8
            case shelfBreakU8: buffer[p] = libraryBreakU8
            default: break
            }
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    public static func contract(_ input: String) -> String {
        var buffer = [UInt8](input.utf8)
        for p in buffer.indices {
            switch buffer[p] {
            case libraryBreakU8: buffer[p] = shelfBreakU8
            case shelfBreakU8: buffer[p] = seriesBreakU8
            case seriesBreakU8: buffer[p] = collectionBreakU8
            case collectionBreakU8: buffer[p] = volumeBreakU8
            case volumeBreakU8: buffer[p] = bookBreakU8
            case bookBreakU8: buffer[p] = chapterBreakU8
            case chapterBreakU8: buffer[p] = sectionBreakU8
            case sectionBreakU8: buffer[p] = scrollBreakU8
            case scrollBreakU8: buffer[p] = lineBreakU8
            default: break
            }
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    // MARK: - summary / maps / index

    public static func createSummary(_ input: String) -> String {
        let bytes = [UInt8](input.utf8)
        var end = 0
        while end < bytes.count {
            if isPhextBreak(bytes[end]) { break }
            end += 1
        }
        var summary = String(decoding: bytes[..<end], as: UTF8.self)
        if end < bytes.count {
            summary += "..."
        }
        return summary
    }

    public static func navmap(_ urlbase: String, _ input: String) -> String {
        let phokens = phokenize(input)
        var result = ""
        if !phokens.isEmpty {
            result += "<ul>\n"
        }
        for phoken in phokens {
            result += "<li><a href=\"\(urlbase)\(phoken.coord.toUrlEncoded())\">\(phoken.coord.toString()) \(createSummary(phoken.scroll))</a></li>\n"
        }
        if !phokens.isEmpty {
            result += "</ul>\n"
        }
        return result
    }

    public static func textmap(_ input: String) -> String {
        var result = ""
        for phoken in phokenize(input) {
            result += "* \(phoken.coord.toString()): \(createSummary(phoken.scroll))\n"
        }
        return result
    }

    static func indexPhokens(_ input: String) -> [PositionedScroll] {
        let phokens = phokenize(input)
        var offset = 0
        var coord = Coordinate()
        var output: [PositionedScroll] = []
        for phoken in phokens {
            let reference = phoken.coord
            while coord.z.library < reference.z.library { coord.libraryBreak(); offset += 1 }
            while coord.z.shelf < reference.z.shelf { coord.shelfBreak(); offset += 1 }
            while coord.z.series < reference.z.series { coord.seriesBreak(); offset += 1 }
            while coord.y.collection < reference.y.collection { coord.collectionBreak(); offset += 1 }
            while coord.y.volume < reference.y.volume { coord.volumeBreak(); offset += 1 }
            while coord.y.book < reference.y.book { coord.bookBreak(); offset += 1 }
            while coord.x.chapter < reference.x.chapter { coord.chapterBreak(); offset += 1 }
            while coord.x.section < reference.x.section { coord.sectionBreak(); offset += 1 }
            while coord.x.scroll < reference.x.scroll { coord.scrollBreak(); offset += 1 }
            output.append(PositionedScroll(coord: coord, scroll: "\(offset)"))
            offset += phoken.scroll.utf8.count
        }
        return output
    }

    public static func index(_ input: String) -> String {
        var output = indexPhokens(input)
        return dephokenize(&output)
    }

    /// The offset of the scroll at `coord`, or of the last scroll before
    /// it. 0 when no scroll comes at or before `coord`.
    public static func offset(_ input: String, _ coord: Coordinate) -> Int {
        var result = 0
        for phoken in indexPhokens(input) {
            if phoken.coord > coord { break }
            result = Int(phoken.scroll) ?? result
        }
        return result
    }

    // MARK: - checksum / manifest / soundex

    /// 128-bit XXH3 checksum as 32 lowercase hex digits, mirroring rs
    /// `checksum` (xxhash-rust xxh3_128, formatted as the 128-bit value).
    /// Resolved via libxxhash at runtime; returns nil when libxxhash is
    /// unavailable on the host.
    public static func checksum(_ input: String) -> String? {
        let bytes = [UInt8](input.utf8)
        var low: UInt64 = 0
        var high: UInt64 = 0
        let rc = bytes.withUnsafeBufferPointer { ptr -> Int32 in
            phext_xxh3_128(ptr.baseAddress, bytes.count, &low, &high)
        }
        guard rc == 0 else { return nil }
        // rs formats the u128 value: high << 64 | low, zero-padded to 32 hex.
        let highHex = String(high, radix: 16)
        let lowHex = String(low, radix: 16)
        return String(repeating: "0", count: 16 - highHex.count) + highHex
            + String(repeating: "0", count: 16 - lowHex.count) + lowHex
    }

    public static func manifest(_ input: String) -> String? {
        var phokens = phokenize(input)
        for i in phokens.indices {
            guard let sum = checksum(phokens[i].scroll) else { return nil }
            phokens[i].scroll = sum
        }
        return dephokenize(&phokens)
    }

    static func soundexInternal(_ byte: String) -> String {
        let letter1 = "bpfv"
        let letter2 = "cskgjqxz"
        let letter3 = "dt"
        let letter4 = "l"
        let letter5 = "mn"
        let letter6 = "r"
        var value = 1
        for c in byte.utf8 {
            if letter1.utf8.contains(c) { value += 1; continue }
            if letter2.utf8.contains(c) { value += 2; continue }
            if letter3.utf8.contains(c) { value += 3; continue }
            if letter4.utf8.contains(c) { value += 4; continue }
            if letter5.utf8.contains(c) { value += 5; continue }
            if letter6.utf8.contains(c) { value += 6; continue }
        }
        return "\(value % 99)"
    }

    public static func soundexV1(_ input: String) -> String {
        var phokens = phokenize(input)
        for i in phokens.indices {
            phokens[i].scroll = soundexInternal(phokens[i].scroll)
        }
        return dephokenize(&phokens)
    }
}
