// Stores.swift — persistent scroll stores for edit sequences (v0.7.0).
//
// The Phext buffer API is buffer-in/buffer-out on immutable strings: every
// insert/replace/remove walks the whole buffer (getSubspaceCoordinates) and
// copies it into a fresh array, and remove additionally re-phokenizes via
// normalize — so a sequence of N edits on a growing phext costs O(N x size).
// The two stores in this file pay the phokenize once, mutate in place, and
// serialize on demand. They are additive: no existing API changes.
//
// Edit semantics are the string path's own, exactly: insert at an existing
// coordinate concatenates old text before new, replace overwrites, fetch
// returns the scroll's text or "". The stores never hold an empty scroll,
// so the degenerate empty-text edits follow the normalized string
// semantics: replace(coord, "") removes (exactly Phext.remove) and insert
// of "" is a no-op. Ported from the proven libphext-py stores
// (phext/dynamic.py, phext/transitive.py).

// MARK: - Coordinate components (canonical order)

extension Coordinate {
    /// Components in canonical order: (library, shelf, series, collection,
    /// volume, book, chapter, section, scroll). The count of this array is
    /// the phext dimension count — the transitive store derives its depth
    /// from it rather than hardcoding 9.
    public var components: [UInt64] {
        [z.library, z.shelf, z.series,
         y.collection, y.volume, y.book,
         x.chapter, x.section, x.scroll]
    }

    public init(components: [UInt64]) {
        precondition(components.count == 9, "a phext coordinate has 9 components")
        self.init(components[0], components[1], components[2],
                  components[3], components[4], components[5],
                  components[6], components[7], components[8])
    }
}

// MARK: - DynamicPhext: capacity-managed dynamic-array store

/// A scroll store over an explicitly capacity-managed array.
///
/// Capacity discipline (CLRS dynamic-table strategy): start at capacity 1,
/// double when full on grow, and shrink ONLY when the load drops to one
/// quarter (n <= capacity/4) — never at half full, which thrashes at a
/// resize boundary. Swift's Array already amortizes its own growth; this
/// store makes the capacity explicit and observable instead: the backing
/// slot array is sized exactly to `capacity`, growth and shrink are
/// performed by hand, and resizes are instrumented (`resizeCount`,
/// `elementsCopied`) so tests can assert the amortized behavior directly.
///
/// Scrolls stay in strictly increasing coordinate order, so `serialize()`
/// is byte-identical to the string path over any edit sequence.
public final class DynamicPhext {
    public static let minimumCapacity = 1

    private var slots: [PositionedScroll?]
    public private(set) var capacity: Int
    public private(set) var count: Int = 0
    public private(set) var resizeCount: Int = 0
    public private(set) var elementsCopied: Int = 0
    /// Load denominator at which the array halves: 4 (quarter-full) is the
    /// correct strategy. 2 reproduces the textbook's bad half-full strategy
    /// and exists so the thrash test can measure it.
    public let shrinkDivisor: Int

    public init(buffer: String = "", shrinkDivisor: Int = 4) {
        precondition(shrinkDivisor >= 2, "shrinkDivisor must be >= 2")
        self.shrinkDivisor = shrinkDivisor
        self.capacity = DynamicPhext.minimumCapacity
        self.slots = [PositionedScroll?](repeating: nil, count: self.capacity)
        if !buffer.isEmpty { load(buffer) }
    }

    // -- capacity machinery --

    private func resize(to newCapacity: Int) {
        var next = [PositionedScroll?](repeating: nil, count: newCapacity)
        for i in 0..<count { next[i] = slots[i] }
        slots = next
        capacity = newCapacity
        resizeCount += 1
        elementsCopied += count
    }

    private func growIfFull() {
        if count == capacity { resize(to: 2 * capacity) }
    }

    private func shrinkIfSparse() {
        // Quarter-full rule: after halving, the load is at most 1/2, so the
        // next grow is at least capacity/4 appends away — no thrash.
        if capacity > DynamicPhext.minimumCapacity && count <= capacity / shrinkDivisor {
            resize(to: max(DynamicPhext.minimumCapacity, capacity / 2))
        }
    }

    public func resetStats() {
        resizeCount = 0
        elementsCopied = 0
    }

    // -- loading and serialization --

    public func load(_ buffer: String) {
        capacity = DynamicPhext.minimumCapacity
        slots = [PositionedScroll?](repeating: nil, count: capacity)
        count = 0
        resetStats()
        for ps in Phext.phokenize(buffer) where !ps.scroll.isEmpty {
            push(ps)
        }
    }

    public func scrolls() -> [PositionedScroll] {
        (0..<count).map { slots[$0]! }
    }

    public func serialize() -> String {
        var tokens = scrolls()
        return Phext.dephokenize(&tokens)
    }

    // -- lookup: binary search over the coordinate-ordered array --

    private func find(_ coord: Coordinate) -> (index: Int, found: Bool) {
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            let here = slots[mid]!.coord
            if here < coord { lo = mid + 1 }
            else if here > coord { hi = mid }
            else { return (mid, true) }
        }
        return (lo, false)
    }

    public func fetch(_ coord: Coordinate) -> String {
        let (index, found) = find(coord)
        return found ? slots[index]!.scroll : ""
    }

    public func contains(_ coord: Coordinate) -> Bool { find(coord).found }

    // -- edits: string-path update semantics, in place --

    private func push(_ ps: PositionedScroll) {
        growIfFull()
        slots[count] = ps
        count += 1
    }

    /// Amortized O(1) tail append; the coordinate must extend the tail so
    /// the array's coordinate order is preserved.
    public func append(_ coord: Coordinate, _ text: String) {
        if count > 0 {
            precondition(coord > slots[count - 1]!.coord,
                         "append requires a coordinate past the current tail")
        }
        if text.isEmpty { return }
        push(PositionedScroll(coord: coord, scroll: text))
    }

    public func update(_ coord: Coordinate, _ text: String, overwrite: Bool) {
        let (index, found) = find(coord)
        if found {
            if text.isEmpty {
                if overwrite { removeAt(index) }
                return
            }
            let newText = overwrite ? text : slots[index]!.scroll + text
            slots[index] = PositionedScroll(coord: coord, scroll: newText)
            return
        }
        if text.isEmpty { return }
        growIfFull()
        var i = count
        while i > index {
            slots[i] = slots[i - 1]
            i -= 1
        }
        slots[index] = PositionedScroll(coord: coord, scroll: text)
        count += 1
    }

    public func insert(_ coord: Coordinate, _ text: String) { update(coord, text, overwrite: false) }
    public func replace(_ coord: Coordinate, _ text: String) { update(coord, text, overwrite: true) }

    private func removeAt(_ index: Int) {
        var i = index
        while i < count - 1 {
            slots[i] = slots[i + 1]
            i += 1
        }
        count -= 1
        slots[count] = nil
        shrinkIfSparse()
    }

    public func remove(_ coord: Coordinate) {
        let (index, found) = find(coord)
        if found { removeAt(index) }
    }
}

// MARK: - BranchingMap: one recursive transitive hash-map type

/// A hash map of dimension `depth` branching into hash maps of one fewer
/// dimension, recursively, down to leaves holding values.
///
/// Keys are component arrays of exactly `depth` elements. Every operation
/// is defined recursively over the hierarchy: one dictionary lookup per
/// level. The depth is a parameter of the instantiation, not of the
/// structure.
public final class BranchingMap<Value> {
    public let depth: Int
    public private(set) var count: Int = 0

    private final class Node {
        var children: [UInt64: Node] = [:]
        var value: Value? = nil
    }

    private let root = Node()

    public init(depth: Int) {
        precondition(depth >= 1, "depth must be >= 1")
        self.depth = depth
    }

    private func check(_ key: [UInt64]) {
        precondition(key.count == depth, "key has \(key.count) components, map depth is \(depth)")
    }

    // -- fetch: one lookup per dimension, recursively --

    public func fetch(_ key: [UInt64]) -> Value? {
        check(key)
        return fetch(root, key, 0)
    }

    private func fetch(_ node: Node, _ key: [UInt64], _ level: Int) -> Value? {
        guard let child = node.children[key[level]] else { return nil }
        if level == depth - 1 { return child.value }
        return fetch(child, key, level + 1)
    }

    public func contains(_ key: [UInt64]) -> Bool { fetch(key) != nil }

    // -- put: descend recursively, branching new maps as needed --

    /// Stores value at key; returns true when a new leaf was created.
    @discardableResult
    public func put(_ key: [UInt64], _ value: Value) -> Bool {
        check(key)
        let created = put(root, key, 0, value)
        if created { count += 1 }
        return created
    }

    private func put(_ node: Node, _ key: [UInt64], _ level: Int, _ value: Value) -> Bool {
        let component = key[level]
        if level == depth - 1 {
            let created = node.children[component] == nil
            let leaf = node.children[component] ?? Node()
            leaf.value = value
            node.children[component] = leaf
            return created
        }
        let child = node.children[component] ?? Node()
        node.children[component] = child
        return put(child, key, level + 1, value)
    }

    // -- remove: recursive, pruning branches left empty --

    @discardableResult
    public func remove(_ key: [UInt64]) -> Bool {
        check(key)
        let removed = remove(root, key, 0)
        if removed { count -= 1 }
        return removed
    }

    private func remove(_ node: Node, _ key: [UInt64], _ level: Int) -> Bool {
        let component = key[level]
        if level == depth - 1 {
            if node.children[component] != nil {
                node.children[component] = nil
                return true
            }
            return false
        }
        guard let child = node.children[component] else { return false }
        let removed = remove(child, key, level + 1)
        if removed && child.children.isEmpty { node.children[component] = nil }
        return removed
    }

    // -- items: recursive traversal, sorted at every level, which is
    //    lexicographic (coordinate) order over the full key --

    public func items() -> [([UInt64], Value)] {
        var out: [([UInt64], Value)] = []
        collect(root, [], &out)
        return out
    }

    private func collect(_ node: Node, _ prefix: [UInt64], _ out: inout [([UInt64], Value)]) {
        for component in node.children.keys.sorted() {
            let child = node.children[component]!
            if let value = child.value {
                out.append((prefix + [component], value))
            } else {
                collect(child, prefix + [component], &out)
            }
        }
    }
}

// MARK: - TransitivePhext: phext store over a BranchingMap

/// Phext scroll store over a `BranchingMap` at depth 9 — one hash-map layer
/// per coordinate dimension, leaves holding scroll text. The depth is
/// derived from `Coordinate`, not hardcoded. Fetch, insert, and remove
/// touch exactly one dictionary per dimension: no sort, no scan, no binary
/// search, and no dependence on how many scrolls the phext holds.
public final class TransitivePhext {
    public let depth: Int
    private var map: BranchingMap<String>

    public init(buffer: String = "") {
        self.depth = Coordinate().components.count
        self.map = BranchingMap<String>(depth: self.depth)
        if !buffer.isEmpty { load(buffer) }
    }

    public var count: Int { map.count }

    // -- loading and serialization --

    public func load(_ buffer: String) {
        map = BranchingMap<String>(depth: depth)
        for ps in Phext.phokenize(buffer) where !ps.scroll.isEmpty {
            map.put(ps.coord.components, ps.scroll)
        }
    }

    public func scrolls() -> [PositionedScroll] {
        map.items().map { PositionedScroll(coord: Coordinate(components: $0.0), scroll: $0.1) }
    }

    public func serialize() -> String {
        var tokens = scrolls()
        return Phext.dephokenize(&tokens)
    }

    // -- lookup: `depth` dictionary lookups, independent of phext size --

    public func fetch(_ coord: Coordinate) -> String {
        map.fetch(coord.components) ?? ""
    }

    public func contains(_ coord: Coordinate) -> Bool { map.contains(coord.components) }

    // -- edits: string-path update semantics, by hash walk --

    public func update(_ coord: Coordinate, _ text: String, overwrite: Bool) {
        let key = coord.components
        if text.isEmpty {
            if overwrite { map.remove(key) }
            return
        }
        var newText = text
        if !overwrite, let existing = map.fetch(key) {
            newText = existing + text
        }
        map.put(key, newText)
    }

    public func insert(_ coord: Coordinate, _ text: String) { update(coord, text, overwrite: false) }
    public func replace(_ coord: Coordinate, _ text: String) { update(coord, text, overwrite: true) }
    public func remove(_ coord: Coordinate) { map.remove(coord.components) }

    /// A hash hierarchy has no tail; append is insert. Kept for API parity
    /// with DynamicPhext, whose append is the amortized-O(1) tail operation.
    public func append(_ coord: Coordinate, _ text: String) { insert(coord, text) }
}

// MARK: - Convenience constructors (parity with the Python port)

extension Phext {
    public static func dynamic(_ buffer: String = "") -> DynamicPhext { DynamicPhext(buffer: buffer) }
    public static func transitive(_ buffer: String = "") -> TransitivePhext { TransitivePhext(buffer: buffer) }
}
