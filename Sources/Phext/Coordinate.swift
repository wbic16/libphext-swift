// Coordinate.swift — phext coordinates, ported from libphext-rs 0.6.0
// (src/phext.rs). Components are UInt64 (rs `usize` on 64-bit platforms)
// and unbounded: the 999 cap was removed in rs 0.4.0.

/// The large-scale Z arm of a phext coordinate: library / shelf / series.
public struct ZCoordinate: Equatable, Hashable, Comparable, CustomStringConvertible {
    public var library: UInt64
    public var shelf: UInt64
    public var series: UInt64

    public init(library: UInt64 = 1, shelf: UInt64 = 1, series: UInt64 = 1) {
        self.library = library
        self.shelf = shelf
        self.series = series
    }

    public static func < (lhs: ZCoordinate, rhs: ZCoordinate) -> Bool {
        (lhs.library, lhs.shelf, lhs.series) < (rhs.library, rhs.shelf, rhs.series)
    }

    public var description: String { "\(library).\(shelf).\(series)" }
}

/// The large-scale Y arm of a phext coordinate: collection / volume / book.
public struct YCoordinate: Equatable, Hashable, Comparable, CustomStringConvertible {
    public var collection: UInt64
    public var volume: UInt64
    public var book: UInt64

    public init(collection: UInt64 = 1, volume: UInt64 = 1, book: UInt64 = 1) {
        self.collection = collection
        self.volume = volume
        self.book = book
    }

    public static func < (lhs: YCoordinate, rhs: YCoordinate) -> Bool {
        (lhs.collection, lhs.volume, lhs.book) < (rhs.collection, rhs.volume, rhs.book)
    }

    public var description: String { "\(collection).\(volume).\(book)" }
}

/// The large-scale X arm of a phext coordinate: chapter / section / scroll.
public struct XCoordinate: Equatable, Hashable, Comparable, CustomStringConvertible {
    public var chapter: UInt64
    public var section: UInt64
    public var scroll: UInt64

    public init(chapter: UInt64 = 1, section: UInt64 = 1, scroll: UInt64 = 1) {
        self.chapter = chapter
        self.section = section
        self.scroll = scroll
    }

    public static func < (lhs: XCoordinate, rhs: XCoordinate) -> Bool {
        (lhs.chapter, lhs.section, lhs.scroll) < (rhs.chapter, rhs.section, rhs.scroll)
    }

    public var description: String { "\(chapter).\(section).\(scroll)" }
}

/// A phext coordinate: z3.z2.z1/y3.y2.y1/x3.x2.x1, defaulting to
/// 1.1.1/1.1.1/1.1.1. Phext is sparse by design: components are unbounded,
/// but materializing a dense graph costs memory proportional to its
/// populated scroll count. Keep graphs sparse.
public struct Coordinate: Equatable, Hashable, Comparable, CustomStringConvertible {
    public var z: ZCoordinate
    public var y: YCoordinate
    public var x: XCoordinate

    public init(z: ZCoordinate = ZCoordinate(), y: YCoordinate = YCoordinate(), x: XCoordinate = XCoordinate()) {
        self.z = z
        self.y = y
        self.x = x
    }

    /// Positional initializer in canonical order:
    /// (library, shelf, series, collection, volume, book, chapter, section, scroll).
    public init(_ library: UInt64, _ shelf: UInt64, _ series: UInt64,
                _ collection: UInt64, _ volume: UInt64, _ book: UInt64,
                _ chapter: UInt64, _ section: UInt64, _ scroll: UInt64) {
        self.z = ZCoordinate(library: library, shelf: shelf, series: series)
        self.y = YCoordinate(collection: collection, volume: volume, book: book)
        self.x = XCoordinate(chapter: chapter, section: section, scroll: scroll)
    }

    public static func < (lhs: Coordinate, rhs: Coordinate) -> Bool {
        if lhs.z != rhs.z { return lhs.z < rhs.z }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.x < rhs.x
    }

    /// Canonical form (z3.z2.z1/y3.y2.y1/x3.x2.x1). Mirrors rs `to_string`:
    /// an invalid coordinate (any component < 1) stringifies to "".
    public var description: String { toString() }

    public func toString() -> String {
        guard validateCoordinate() else { return "" }
        return "\(z)/\(y)/\(x)"
    }

    public func toUrlEncoded() -> String {
        guard validateCoordinate() else { return "" }
        return "\(z.library).\(z.shelf).\(z.series);\(y.collection).\(y.volume).\(y.book);\(x.chapter).\(x.section).\(x.scroll)"
    }

    public func validateCoordinate() -> Bool {
        z.library >= Phext.coordinateMinimum && z.shelf >= Phext.coordinateMinimum && z.series >= Phext.coordinateMinimum
            && y.collection >= Phext.coordinateMinimum && y.volume >= Phext.coordinateMinimum && y.book >= Phext.coordinateMinimum
            && x.chapter >= Phext.coordinateMinimum && x.section >= Phext.coordinateMinimum && x.scroll >= Phext.coordinateMinimum
    }

    private static func advance(_ index: UInt64) -> UInt64 { index + 1 }

    public mutating func scrollBreak() {
        x.scroll = Coordinate.advance(x.scroll)
    }

    public mutating func sectionBreak() {
        x.section = Coordinate.advance(x.section)
        x.scroll = 1
    }

    public mutating func chapterBreak() {
        x.chapter = Coordinate.advance(x.chapter)
        x.section = 1
        x.scroll = 1
    }

    public mutating func bookBreak() {
        y.book = Coordinate.advance(y.book)
        x.chapter = 1
        x.section = 1
        x.scroll = 1
    }

    public mutating func volumeBreak() {
        y.volume = Coordinate.advance(y.volume)
        y.book = 1
        x.chapter = 1
        x.section = 1
        x.scroll = 1
    }

    public mutating func collectionBreak() {
        y.collection = Coordinate.advance(y.collection)
        y.volume = 1
        y.book = 1
        x.chapter = 1
        x.section = 1
        x.scroll = 1
    }

    public mutating func seriesBreak() {
        z.series = Coordinate.advance(z.series)
        y.collection = 1
        y.volume = 1
        y.book = 1
        x.chapter = 1
        x.section = 1
        x.scroll = 1
    }

    public mutating func shelfBreak() {
        z.shelf = Coordinate.advance(z.shelf)
        z.series = 1
        y.collection = 1
        y.volume = 1
        y.book = 1
        x.chapter = 1
        x.section = 1
        x.scroll = 1
    }

    public mutating func libraryBreak() {
        z.library = Coordinate.advance(z.library)
        z.shelf = 1
        z.series = 1
        y.collection = 1
        y.volume = 1
        y.book = 1
        x.chapter = 1
        x.section = 1
        x.scroll = 1
    }
}

/// Error returned by the strict coordinate parser (rs `PhextParseError`).
public struct PhextParseError: Error, CustomStringConvertible {
    public init() {}
    public var description: String { "Phext addresses are of the form LB.SF.SR/CN.VM.BK/CH.SN.SC" }
}

extension Coordinate {
    /// Strict parse, mirroring rs `TryFrom<&str> for Coordinate`: exactly
    /// three `/`-separated arms of exactly three `.`-separated unsigned
    /// components each; anything else (non-numeric, empty, negative,
    /// overflowing) is an error, never a panic.
    public static func parse(_ value: String) throws -> Coordinate {
        let parts = Phext.splitOn(value, "/")
        guard parts.count == 3 else { throw PhextParseError() }
        let zParts = Phext.splitOn(parts[0], ".")
        let yParts = Phext.splitOn(parts[1], ".")
        let xParts = Phext.splitOn(parts[2], ".")
        guard zParts.count == 3, yParts.count == 3, xParts.count == 3 else { throw PhextParseError() }
        // Rust's usize::from_str accepts an optional leading '+' and ASCII
        // digits only; mirror that exactly.
        func component(_ s: String) throws -> UInt64 {
            var digits = s
            if digits.hasPrefix("+") { digits = String(digits.dropFirst()) }
            guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                  let v = UInt64(digits) else { throw PhextParseError() }
            return v
        }
        return Coordinate(
            try component(zParts[0]), try component(zParts[1]), try component(zParts[2]),
            try component(yParts[0]), try component(yParts[1]), try component(yParts[2]),
            try component(xParts[0]), try component(xParts[1]), try component(xParts[2])
        )
    }
}

/// A scroll together with the coordinate it sits at.
public struct PositionedScroll: Equatable, Comparable, CustomStringConvertible {
    public var coord: Coordinate
    public var scroll: String

    public init(coord: Coordinate = Coordinate(), scroll: String = "") {
        self.coord = coord
        self.scroll = scroll
    }

    public static func < (lhs: PositionedScroll, rhs: PositionedScroll) -> Bool {
        lhs.coord < rhs.coord
    }

    public var description: String { "\(coord): \(String(scroll.prefix(4)))" }
}

/// A range between two coordinates (rs `Range`).
public struct PhextRange: Equatable, CustomStringConvertible {
    public var start: Coordinate
    public var end: Coordinate

    public init(start: Coordinate = Coordinate(), end: Coordinate = Coordinate()) {
        self.start = start
        self.end = end
    }

    public var description: String { "\(start)-\(end)" }
}
