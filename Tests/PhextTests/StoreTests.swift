// StoreTests.swift — v0.7.0 persistent stores: equivalence vs the original
// string path after every operation, capacity/thrash discipline, and
// BranchingMap genericity. Mirrors libphext-py's tests/test_stores.py.

import XCTest
@testable import Phext

/// Deterministic RNG (SplitMix64) so the edit sequence is seeded and
/// reproducible across runs and platforms.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class StoreTests: XCTestCase {
    private func coordPool() -> [Coordinate] {
        var pool: [Coordinate] = []
        for chapter: UInt64 in 1...2 {
            for section: UInt64 in 1...4 {
                for scroll: UInt64 in 1...5 {
                    pool.append(Coordinate(1, 1, 1, 1, 1, 1, chapter, section, scroll))
                    pool.append(Coordinate(1, 1, 1, 1, 1, 2, chapter, section, scroll))
                    pool.append(Coordinate(1, 1, 2, 1, 2, 1, chapter, section, scroll))
                    pool.append(Coordinate(2, 1, 1, 2, 1, 1, chapter, section, scroll))
                }
            }
        }
        return pool // 160 coordinates
    }

    /// Seeded random edit sequence (480 ops): after EVERY operation, both
    /// stores' serializations must equal the string path's buffer exactly,
    /// and fetches must agree.
    func testSeededEquivalenceBothStores() {
        let pool = coordPool()
        let texts = ["alpha", "beta gamma", "delta\nepsilon", "x", "scroll text 123", "Ωμέγα"]
        var rng = SplitMix64(seed: 20261124)
        var buffer = ""
        let dyn = DynamicPhext()
        let trans = TransitivePhext()
        for op in 0..<480 {
            let coord = pool[Int(rng.next() % UInt64(pool.count))]
            let text = texts[Int(rng.next() % UInt64(texts.count))]
            switch rng.next() % 4 {
            case 0:
                buffer = Phext.insert(buffer, coord, text)
                dyn.insert(coord, text); trans.insert(coord, text)
            case 1:
                buffer = Phext.replace(buffer, coord, text)
                dyn.replace(coord, text); trans.replace(coord, text)
            case 2:
                buffer = Phext.remove(buffer, coord)
                dyn.remove(coord); trans.remove(coord)
            default:
                XCTAssertEqual(dyn.fetch(coord), Phext.fetch(buffer, coord), "dynamic fetch, op \(op)")
                XCTAssertEqual(trans.fetch(coord), Phext.fetch(buffer, coord), "transitive fetch, op \(op)")
            }
            XCTAssertEqual(dyn.serialize(), buffer, "dynamic serialize after op \(op)")
            XCTAssertEqual(trans.serialize(), buffer, "transitive serialize after op \(op)")
        }
    }

    func testEmptyTextSemantics() {
        let c = Coordinate(1, 1, 1, 1, 1, 1, 1, 1, 1)
        let dyn = DynamicPhext(); let trans = TransitivePhext()
        dyn.insert(c, ""); trans.insert(c, "")
        XCTAssertEqual(dyn.count, 0); XCTAssertEqual(trans.count, 0)
        dyn.insert(c, "hi"); trans.insert(c, "hi")
        dyn.replace(c, ""); trans.replace(c, "")
        XCTAssertEqual(dyn.count, 0); XCTAssertEqual(trans.count, 0)
        XCTAssertEqual(dyn.serialize(), Phext.remove(Phext.insert("", c, "hi"), c))
        XCTAssertEqual(trans.serialize(), "")
    }

    func testInsertConcatenatesReplaceOverwrites() {
        let c = Coordinate(1, 1, 1, 1, 1, 1, 1, 2, 3)
        let dyn = DynamicPhext(); let trans = TransitivePhext()
        dyn.insert(c, "old"); trans.insert(c, "old")
        dyn.insert(c, "+new"); trans.insert(c, "+new")
        XCTAssertEqual(dyn.fetch(c), "old+new"); XCTAssertEqual(trans.fetch(c), "old+new")
        dyn.replace(c, "fresh"); trans.replace(c, "fresh")
        XCTAssertEqual(dyn.fetch(c), "fresh"); XCTAssertEqual(trans.fetch(c), "fresh")
        XCTAssertEqual(dyn.fetch(Coordinate(9, 9, 9, 9, 9, 9, 9, 9, 9)), "")
        XCTAssertEqual(trans.fetch(Coordinate(9, 9, 9, 9, 9, 9, 9, 9, 9)), "")
    }

    /// Growth: 1,000 appends -> exactly 10 resizes, 1,023 elements copied (< 2N).
    func testGrowthAmortized() {
        let store = DynamicPhext()
        for i in 0..<1000 {
            store.append(Coordinate(1, 1, 1, 1, 1, 1, 1, UInt64(i / 50 + 1), UInt64(i % 50 + 1)), "t\(i)")
        }
        XCTAssertEqual(store.count, 1000)
        XCTAssertEqual(store.resizeCount, 10)
        XCTAssertEqual(store.elementsCopied, 1023)
        XCTAssertEqual(store.capacity, 1024)
    }

    /// No shrink at half-full: capacity holds at 64 with 32 live; halves at 16.
    func testNoShrinkAtHalfFull() {
        let store = DynamicPhext()
        var coords: [Coordinate] = []
        for i in 0..<64 {
            let c = Coordinate(1, 1, 1, 1, 1, 1, 1, UInt64(i / 8 + 1), UInt64(i % 8 + 1))
            coords.append(c); store.append(c, "v")
        }
        XCTAssertEqual(store.capacity, 64)
        for c in coords[32..<64] { store.remove(c) }
        XCTAssertEqual(store.count, 32)
        XCTAssertEqual(store.capacity, 64) // half full: NO shrink
        for c in coords[16..<32] { store.remove(c) }
        XCTAssertEqual(store.count, 16)
        XCTAssertEqual(store.capacity, 32) // quarter full: halved
    }

    /// Thrash: at a 64-scroll boundary over 50 alternating append/remove
    /// pairs, the quarter-full store copies 64 elements total; the half-full
    /// variant copies 6,400 — 100x.
    func testThrashQuarterVsHalf() {
        func run(shrinkDivisor: Int) -> Int {
            let store = DynamicPhext(shrinkDivisor: shrinkDivisor)
            for i in 0..<64 {
                store.append(Coordinate(1, 1, 1, 1, 1, 1, 1, UInt64(i / 8 + 1), UInt64(i % 8 + 1)), "v")
            }
            store.resetStats()
            let tail = Coordinate(1, 1, 1, 1, 1, 1, 2, 1, 1)
            for _ in 0..<50 {
                store.append(tail, "tail")
                store.remove(tail)
            }
            return store.elementsCopied
        }
        XCTAssertEqual(run(shrinkDivisor: 4), 64)
        XCTAssertEqual(run(shrinkDivisor: 2), 6400)
    }

    /// BranchingMap is one recursive type: the same code at depths 3 and 1.
    func testBranchingMapGenericity() {
        let m3 = BranchingMap<String>(depth: 3)
        m3.put([2, 1, 1], "b"); m3.put([1, 1, 2], "a2"); m3.put([1, 1, 1], "a1")
        XCTAssertEqual(m3.count, 3)
        XCTAssertEqual(m3.fetch([1, 1, 2]), "a2")
        XCTAssertNil(m3.fetch([9, 9, 9]))
        XCTAssertEqual(m3.items().map { $0.1 }, ["a1", "a2", "b"]) // sorted order
        XCTAssertTrue(m3.remove([1, 1, 1]))
        XCTAssertEqual(m3.count, 2)
        XCTAssertFalse(m3.remove([1, 1, 1]))

        let m1 = BranchingMap<String>(depth: 1)
        m1.put([7], "seven")
        XCTAssertEqual(m1.fetch([7]), "seven")
        XCTAssertEqual(m1.items().map { $0.0 }, [[7]])
    }

    func testTransitiveDepthDerivedFromCoordinate() {
        XCTAssertEqual(TransitivePhext().depth, 9)
        XCTAssertEqual(TransitivePhext().depth, Coordinate().components.count)
    }

    func testLoadFromBufferRoundTrip() {
        var buffer = ""
        buffer = Phext.insert(buffer, Coordinate(1, 1, 1, 1, 1, 1, 1, 1, 2), "second")
        buffer = Phext.insert(buffer, Coordinate(1, 1, 1, 1, 1, 1, 1, 1, 1), "first")
        buffer = Phext.insert(buffer, Coordinate(1, 1, 1, 1, 1, 1, 3, 1, 1), "chapter three")
        XCTAssertEqual(DynamicPhext(buffer: buffer).serialize(), buffer)
        XCTAssertEqual(TransitivePhext(buffer: buffer).serialize(), buffer)
        XCTAssertEqual(Phext.dynamic(buffer).serialize(), buffer)
        XCTAssertEqual(Phext.transitive(buffer).serialize(), buffer)
    }
}
