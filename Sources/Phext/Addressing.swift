// Addressing.swift — point, offset, and range addressing, ported 1:1 from
// libphext-rs 0.6.1 (src/phext.rs, addressing section). Spec:
// RANGE-SYNTAX-PROPOSAL.md (ratified by Will, 2026-11-15).
//
// A point address is "[$N:]<9D coordinate>@<line>,<column>": the multiverse
// prefix and the coordinate exactly as in parseUniverseAddress, plus a
// within-scroll caret position. Line and column are 1-based; a position
// names a caret boundary (column 1 is the boundary before the line's first
// character; a line of n characters has valid columns 1..n+1), and columns
// count Unicode scalar values. A point may carry "+<offsetChars>": select
// forward that many characters (scalars) from the point, counted within
// the scroll, terminating at the scroll boundary.
//
// A range address is two point addresses joined by one hyphen:
// "<point>-<point>". The endpoints may span scrolls and universes; an
// endpoint without "@" names its whole scroll (as start: its first
// boundary; as end: its last). Canonical form: endpoints in ascending
// (universe, coordinate, line, column) order — direction is discarded —
// "$1:" never written, integers in minimal decimal form. Out-of-range
// endpoints fail at resolution, never clamp.

/// A caret boundary inside one scroll: 1-based line and column (see the
/// section note above).
public struct ScrollPosition: Equatable, Comparable, CustomStringConvertible {
    public var line: UInt64
    public var column: UInt64

    public init(line: UInt64 = 1, column: UInt64 = 1) {
        self.line = line
        self.column = column
    }

    public static func < (lhs: ScrollPosition, rhs: ScrollPosition) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }

    public var description: String { "\(line),\(column)" }
}

/// One parsed point address: universe (1-based; 1 when the "$N:" prefix
/// is absent), the 9D coordinate, an optional caret position, and an
/// optional forward offset in characters.
public struct PointAddress: Equatable, CustomStringConvertible {
    public var universe: UInt64
    public var coordinate: Coordinate
    public var position: ScrollPosition?
    public var offset: UInt64?

    public init(universe: UInt64 = 1, coordinate: Coordinate = Coordinate(),
                position: ScrollPosition? = nil, offset: UInt64? = nil) {
        self.universe = universe
        self.coordinate = coordinate
        self.position = position
        self.offset = offset
    }

    /// Canonical form: "$1:" never written, minimal decimal integers.
    public var description: String {
        var result = ""
        if universe > 1 { result += "$\(universe):" }
        result += coordinate.toString()
        if let pos = position {
            result += "@\(pos.line),\(pos.column)"
            if let offset = offset {
                result += "+\(offset)"
            }
        }
        return result
    }
}

/// A parsed range: two point endpoints, normalized to ascending order at
/// parse time.
public struct RangeAddress: Equatable, CustomStringConvertible {
    public var start: PointAddress
    public var end: PointAddress

    public init(start: PointAddress, end: PointAddress) {
        self.start = start
        self.end = end
    }

    public var description: String { "\(start)-\(end)" }
}

extension Phext {
    /// rs `parse_address_uint`: ASCII digits only, at least one, no sign,
    /// no overflow.
    static func parseAddressUInt(_ text: Substring) -> UInt64? {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return UInt64(text)
    }

    /// rs `parse_address_coordinate`: exactly three `/`-separated arms of
    /// exactly three `.`-separated components, each >= 1. (rs builds the
    /// canonical string and runs it through the lenient `to_coordinate`;
    /// with all components validated >= 1 that is the identity, so the
    /// coordinate is constructed directly.)
    static func parseAddressCoordinate(_ text: Substring) -> Coordinate? {
        let arms = text.split(separator: "/", omittingEmptySubsequences: false)
        guard arms.count == 3 else { return nil }
        var values: [UInt64] = []
        for arm in arms {
            let parts = arm.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            for part in parts {
                guard let value = parseAddressUInt(part), value >= 1 else { return nil }
                values.append(value)
            }
        }
        return Coordinate(values[0], values[1], values[2],
                          values[3], values[4], values[5],
                          values[6], values[7], values[8])
    }

    /// Parses a v0.6.1 point address:
    /// "[$N:]<coordinate>[@<line>,<column>[+<offsetChars>]]". Returns nil
    /// on any malformed input: universe 0, a coordinate component below
    /// 1, a line or column below 1, a sign anywhere, or trailing
    /// structure. "$1:" is accepted on input; the canonical description
    /// never emits it.
    public static func parsePointAddress(_ address: String) -> PointAddress? {
        var universe: UInt64 = 1
        var rest = Substring(address)
        if rest.hasPrefix("$") {
            let stripped = rest.dropFirst()
            guard let colon = stripped.firstIndex(of: ":") else { return nil }
            guard let n = parseAddressUInt(stripped[..<colon]), n >= 1 else { return nil }
            universe = n
            rest = stripped[stripped.index(after: colon)...]
        }
        var coordPart = rest
        var posPart: Substring? = nil
        if let at = rest.firstIndex(of: "@") {
            let pos = rest[rest.index(after: at)...]
            if pos.contains("@") { return nil }
            coordPart = rest[..<at]
            posPart = pos
        }
        guard let coordinate = parseAddressCoordinate(coordPart) else { return nil }
        var position: ScrollPosition? = nil
        var offset: UInt64? = nil
        if let pos = posPart {
            guard let comma = pos.firstIndex(of: ",") else { return nil }
            guard let line = parseAddressUInt(pos[..<comma]) else { return nil }
            let colPart = pos[pos.index(after: comma)...]
            var colText = colPart
            var offsetValue: UInt64? = nil
            if let plus = colPart.firstIndex(of: "+") {
                colText = colPart[..<plus]
                guard let off = parseAddressUInt(colPart[colPart.index(after: plus)...]) else { return nil }
                offsetValue = off
            }
            guard let column = parseAddressUInt(colText) else { return nil }
            guard line >= 1, column >= 1 else { return nil }
            position = ScrollPosition(line: line, column: column)
            offset = offsetValue
        }
        return PointAddress(universe: universe, coordinate: coordinate, position: position, offset: offset)
    }

    /// rs `endpoint_position_key`: a missing "@" sorts by role — on the
    /// start endpoint it is the scroll's first boundary, on the end
    /// endpoint its last.
    static func endpointPositionKey(_ point: PointAddress, _ isStart: Bool) -> (UInt64, UInt64) {
        if let pos = point.position { return (pos.line, pos.column) }
        return isStart ? (1, 1) : (UInt64.max, UInt64.max)
    }

    /// rs `endpoint_cmp`: (universe, coordinate, line, column) order.
    /// Returns -1, 0, or 1.
    static func endpointCmp(_ a: PointAddress, _ aIsStart: Bool,
                            _ b: PointAddress, _ bIsStart: Bool) -> Int {
        if a.universe != b.universe { return a.universe < b.universe ? -1 : 1 }
        if a.coordinate != b.coordinate { return a.coordinate < b.coordinate ? -1 : 1 }
        let ka = endpointPositionKey(a, aIsStart)
        let kb = endpointPositionKey(b, bIsStart)
        if ka != kb { return ka < kb ? -1 : 1 }
        return 0
    }

    /// Parses a v0.6.1 range address: exactly two point addresses joined
    /// by one hyphen. The endpoints are normalized to ascending order
    /// (direction is discarded, per the ratified spec). Range endpoints
    /// may not carry a "+offset" — the offset form never takes a second
    /// endpoint. Returns nil on malformed input.
    public static func parseRangeAddress(_ address: String) -> RangeAddress? {
        guard let hyphen = address.firstIndex(of: "-") else { return nil }
        let first = address[..<hyphen]
        let second = address[address.index(after: hyphen)...]
        if second.contains("-") { return nil }
        guard let a = parsePointAddress(String(first)),
              let b = parsePointAddress(String(second)) else { return nil }
        if a.offset != nil || b.offset != nil { return nil }
        if endpointCmp(a, true, b, false) > 0 {
            return RangeAddress(start: b, end: a)
        }
        return RangeAddress(start: a, end: b)
    }

    /// Resolves a caret position inside one scroll to a character
    /// (Unicode scalar) offset. Nil when the line or column is past the
    /// scroll's extent — never clamps.
    static func resolveScrollOffset(_ text: String, _ pos: ScrollPosition) -> Int? {
        guard pos.line >= 1, pos.column >= 1 else { return nil }
        var line: UInt64 = 1
        var column: UInt64 = 1
        var offset = 0
        for scalar in text.unicodeScalars {
            if line == pos.line && column == pos.column { return offset }
            if scalar.value == 0x0A { line += 1; column = 1 } else { column += 1 }
            offset += 1
        }
        if line == pos.line && column == pos.column { return offset }
        return nil
    }

    /// The scroll text at a coordinate in one member phext, in the
    /// phokenize sense of presence: a coordinate is present exactly when
    /// phokenize enumerates it.
    static func addressedScrollText(_ member: String, _ target: Coordinate) -> String? {
        phokenize(member).first(where: { $0.coord == target })?.scroll
    }
}

extension Chain {
    /// Resolves a point address against this chain: (universe,
    /// coordinate, character offset within the scroll). A point without
    /// "@" resolves to offset 0 of its scroll. Nil when the universe or
    /// scroll is absent or the position is out of range — never clamps.
    public func resolvePoint(_ point: PointAddress) -> (UInt64, Coordinate, Int)? {
        guard point.universe >= 1, point.universe <= UInt64(members.count) else { return nil }
        guard let text = Phext.addressedScrollText(members[Int(point.universe - 1)], point.coordinate) else { return nil }
        let offset: Int
        if let pos = point.position {
            guard let resolved = Phext.resolveScrollOffset(text, pos) else { return nil }
            offset = resolved
        } else {
            offset = 0
        }
        return (point.universe, point.coordinate, offset)
    }

    /// Fetches a point address string. A bare point is a caret: it
    /// fetches the empty string. The offset form fetches the selected
    /// characters: from the point, forward `offset` characters (Unicode
    /// scalars) within the scroll, terminating at the scroll boundary.
    /// Any parse or resolution failure fetches the empty string, as
    /// `Chain.fetch` does.
    public func fetchPoint(_ address: String) -> String {
        guard let point = Phext.parsePointAddress(address) else { return "" }
        guard let count = point.offset else { return "" }
        guard let (_, _, offset) = resolvePoint(point) else { return "" }
        let text = Phext.addressedScrollText(members[Int(point.universe - 1)], point.coordinate) ?? ""
        var result = ""
        var remaining = count
        for scalar in text.unicodeScalars.dropFirst(offset) {
            if remaining == 0 { break }
            result.unicodeScalars.append(scalar)
            remaining -= 1
        }
        return result
    }

    /// Resolves a range against this chain into per-scroll segments:
    /// (universe, coordinate, segment text) in ascending order. Middle
    /// scrolls contribute their whole text; the endpoint scrolls
    /// contribute from/to their endpoint boundaries (an endpoint without
    /// "@" contributes its whole scroll). Nil when either endpoint fails
    /// to resolve — an out-of-range endpoint is an error, never a clamp.
    public func resolveRange(_ range: RangeAddress) -> [(UInt64, Coordinate, String)]? {
        let start = range.start
        let end = range.end
        guard start.universe >= 1, end.universe <= UInt64(members.count),
              start.universe <= end.universe else { return nil }
        // both endpoint scrolls must be present, and both endpoint
        // positions must resolve
        guard resolvePoint(PointAddress(universe: start.universe, coordinate: start.coordinate,
                                        position: start.position, offset: nil)) != nil else { return nil }
        guard resolvePoint(PointAddress(universe: end.universe, coordinate: end.coordinate,
                                        position: end.position, offset: nil)) != nil else { return nil }
        var segments: [(UInt64, Coordinate, String)] = []
        for universe in start.universe...end.universe {
            let member = members[Int(universe - 1)]
            let scrolls = Phext.phokenize(member).sorted()
            for ps in scrolls {
                let coord = ps.coord
                if universe == start.universe && coord < start.coordinate { continue }
                if universe == end.universe && coord > end.coordinate { continue }
                let scalars = Array(ps.scroll.unicodeScalars)
                var lo = 0
                var hi = scalars.count
                if universe == start.universe && coord == start.coordinate {
                    if let pos = start.position {
                        guard let resolved = Phext.resolveScrollOffset(ps.scroll, pos) else { return nil }
                        lo = resolved
                    }
                }
                if universe == end.universe && coord == end.coordinate {
                    if let pos = end.position {
                        guard let resolved = Phext.resolveScrollOffset(ps.scroll, pos) else { return nil }
                        hi = resolved
                    }
                }
                if lo > hi { return nil }
                var segment = ""
                segment.unicodeScalars.append(contentsOf: scalars[lo..<hi])
                segments.append((universe, coord, segment))
            }
        }
        return segments
    }

    /// Fetches a range address string: the spanned text with phext
    /// structure bytes preserved — the covered segments re-assembled at
    /// their coordinates into a phext (chain) fragment (scroll breaks
    /// between covered scrolls inside a universe, CHAIN_BREAK between
    /// universes, never a trailing CHAIN_CLOSE: a fragment is an
    /// excerpt, not a terminated chain), so the result round-trips as a
    /// phext fragment. Empty segments contribute nothing. Any parse or
    /// resolution failure fetches the empty string, as `Chain.fetch`
    /// does.
    public func fetchRange(_ address: String) -> String {
        guard let range = Phext.parseRangeAddress(address) else { return "" }
        guard let segments = resolveRange(range) else { return "" }
        var newMembers: [String] = []
        for universe in range.start.universe...range.end.universe {
            var member = ""
            for (segUniverse, coord, text) in segments where segUniverse == universe {
                if !text.isEmpty {
                    member = Phext.insert(member, coord, text)
                }
            }
            newMembers.append(member)
        }
        return Chain(members: newMembers, closed: false).serialize()
    }
}
