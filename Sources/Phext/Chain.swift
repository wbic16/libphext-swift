// Chain.swift — chains and multiverse addressing, ported 1:1 from
// libphext-rs 0.6.0 (src/phext.rs, chain layer).
//
// A chain is an ordered series of complete phexts within one stream,
// joined by CHAIN_BREAK (0x02) and optionally terminated by CHAIN_CLOSE
// (0x03). `closed` is true only when a CHAIN_CLOSE terminated the chain;
// a chain ending at EOF is unclosed and never silently promoted. A
// stream with no chain bytes at all is a single unclosed chain holding
// one member: every pre-0.6 phext reads this way.

public struct Chain: Equatable {
    public var members: [String]
    public var closed: Bool

    public init(members: [String] = [], closed: Bool = false) {
        self.members = members
        self.closed = closed
    }

    /// Serializes this chain alone: members joined by CHAIN_BREAK, with
    /// a trailing CHAIN_CLOSE when closed.
    public func serialize() -> String {
        var result = ""
        var first = true
        for member in members {
            if !first { result.append(Phext.chainBreak) }
            first = false
            result += member
        }
        if closed { result.append(Phext.chainClose) }
        return result
    }

    /// Fetch a scroll by multiverse address: "$N:coord", or a bare
    /// coordinate (universe 1). Out-of-range universes, malformed
    /// universe prefixes, and missing scrolls all yield "" — the same
    /// value as a present-but-empty scroll. There is no error channel.
    public func fetch(_ address: String) -> String {
        guard let (universe, coord) = Phext.parseUniverseAddress(address) else {
            return ""
        }
        guard universe >= 1, universe - 1 < UInt64(members.count) else {
            return ""
        }
        return Phext.fetch(members[Int(universe - 1)], coord)
    }
}

extension Phext {
    /// Splits a stream into its chains. Splitting follows rs `split_on`
    /// semantics, so empty members and empty chains are preserved
    /// exactly: parse and serialize are byte-exact inverses for every
    /// stream, including the empty stream.
    public static func parseChains(_ input: String) -> [Chain] {
        let endsClosed = input.hasSuffix(String(chainClose))
        var segments = splitOn(input, chainClose)
        if endsClosed {
            // splitOn preserves the empty tail after a trailing
            // delimiter; that tail is the end of the stream, not the
            // start of another chain.
            segments.removeLast()
        }
        let count = segments.count
        var chains: [Chain] = []
        for (i, segment) in segments.enumerated() {
            let closed = endsClosed || (i + 1 < count)
            chains.append(Chain(members: splitOn(segment, chainBreak), closed: closed))
        }
        return chains
    }

    /// Serializes a stream of chains back into stream bytes: the
    /// inverse of `parseChains`.
    public static func serializeChains(_ chains: [Chain]) -> String {
        var result = ""
        for chain in chains {
            result += chain.serialize()
        }
        return result
    }

    /// Parses a multiverse address into (universe, coordinate), or nil
    /// when the universe prefix is malformed ($0:, a missing colon, or
    /// a non-numeric universe). A bare address is universe 1. The
    /// coordinate part uses the lenient rs `to_coordinate`, as rs does.
    public static func parseUniverseAddress(_ address: String) -> (UInt64, Coordinate)? {
        if address.hasPrefix("$") {
            let rest = String(address.dropFirst())
            guard let colon = rest.firstIndex(of: ":") else { return nil }
            let num = String(rest[..<colon])
            let coordPart = String(rest[rest.index(after: colon)...])
            // Mirror Rust's usize parse: optional leading '+', ASCII
            // digits, at least one digit, no overflow.
            var digits = num
            if digits.hasPrefix("+") { digits = String(digits.dropFirst()) }
            guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                  let n = UInt64(digits) else { return nil }
            if n < 1 { return nil }
            return (n, toCoordinate(coordPart))
        }
        return (1, toCoordinate(address))
    }
}
