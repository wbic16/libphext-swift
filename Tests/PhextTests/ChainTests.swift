// ChainTests.swift — ported 1:1 from libphext-rs 0.6.0 src/test_chain.rs
// (plus the multiverse addressing tests at the end of src/phext.rs).

import XCTest
@testable import Phext

final class ChainTests: XCTestCase {
    private func roundtrip(_ stream: String) {
        let chains = Phext.parseChains(stream)
        XCTAssertEqual(Phext.serializeChains(chains), stream, "round trip \(stream.debugDescription)")
    }

    func testChainFreeInputIsOneUnclosedChain() {
        let doc = "alpha\u{17}beta\u{01}gamma"
        let chains = Phext.parseChains(doc)
        XCTAssertEqual(chains.count, 1)
        XCTAssertEqual(chains[0].members, [doc])
        XCTAssertFalse(chains[0].closed)
        XCTAssertEqual(Phext.serializeChains(chains), doc)
        XCTAssertEqual(Phext.fetch(doc, Phext.toCoordinate("1.1.1/1.1.1/1.1.2")), "beta")
        XCTAssertEqual(Phext.fetch(doc, Phext.toCoordinate("2.1.1/1.1.1/1.1.1")), "gamma")
        roundtrip(doc)
    }

    func testTwoPhextsChainedAndClosedRoundTrip() {
        let stream = "edition one\u{02}edition two\u{03}"
        let chains = Phext.parseChains(stream)
        XCTAssertEqual(chains.count, 1)
        XCTAssertEqual(chains[0].members, ["edition one", "edition two"])
        XCTAssertTrue(chains[0].closed)
        roundtrip(stream)
    }

    func testUnclosedChainAtEOFReportsTruncated() {
        let chains = Phext.parseChains("one\u{02}two")
        XCTAssertEqual(chains.count, 1)
        XCTAssertEqual(chains[0].members, ["one", "two"])
        XCTAssertFalse(chains[0].closed)
        roundtrip("one\u{02}two")
    }

    func testTwoChainsInOneStreamParseAsTwoUnits() {
        let stream = "a\u{02}b\u{03}c\u{02}d\u{03}"
        let chains = Phext.parseChains(stream)
        XCTAssertEqual(chains.count, 2)
        XCTAssertEqual(chains[0].members, ["a", "b"])
        XCTAssertTrue(chains[0].closed)
        XCTAssertEqual(chains[1].members, ["c", "d"])
        XCTAssertTrue(chains[1].closed)
        roundtrip(stream)

        let mixed = Phext.parseChains("a\u{03}b")
        XCTAssertEqual(mixed.count, 2)
        XCTAssertEqual(mixed[0].members, ["a"])
        XCTAssertTrue(mixed[0].closed)
        XCTAssertEqual(mixed[1].members, ["b"])
        XCTAssertFalse(mixed[1].closed)
        roundtrip("a\u{03}b")
    }

    func testChainedMembersCarryFullPhexts() {
        let first = "root\u{17}second scroll"
        let second = Phext.insert("", Phext.toCoordinate("1.1.1/1.1.1/1.1.3"), "third edition")
        let stream = "\(first)\u{02}\(second)\u{03}"
        let chains = Phext.parseChains(stream)
        XCTAssertEqual(chains.count, 1)
        XCTAssertEqual(chains[0].members.count, 2)
        XCTAssertEqual(Phext.fetch(chains[0].members[0], Phext.toCoordinate("1.1.1/1.1.1/1.1.2")), "second scroll")
        XCTAssertEqual(Phext.fetch(chains[0].members[1], Phext.toCoordinate("1.1.1/1.1.1/1.1.3")), "third edition")
        XCTAssertEqual(Phext.fetch(chains[0].members[1], Phext.toCoordinate("1.1.1/1.1.1/1.1.1")), "")
        roundtrip(stream)
    }

    func testEditionsInSuccessionReadInOrder() {
        let chains = Phext.parseChains("v1\u{02}v2\u{02}v3\u{03}")
        XCTAssertEqual(chains.count, 1)
        XCTAssertEqual(chains[0].members, ["v1", "v2", "v3"])
        XCTAssertTrue(chains[0].closed)
        roundtrip("v1\u{02}v2\u{02}v3\u{03}")
    }

    func testEmptyAndBreakOnlyStreamsRoundTrip() {
        let empty = Phext.parseChains("")
        XCTAssertEqual(empty.count, 1)
        XCTAssertEqual(empty[0].members, [""])
        XCTAssertFalse(empty[0].closed)
        roundtrip("")

        let loneClose = Phext.parseChains("\u{03}")
        XCTAssertEqual(loneClose.count, 1)
        XCTAssertEqual(loneClose[0].members, [""])
        XCTAssertTrue(loneClose[0].closed)
        roundtrip("\u{03}")

        XCTAssertEqual(Phext.parseChains("a\u{02}")[0].members, ["a", ""])
        XCTAssertEqual(Phext.parseChains("\u{02}b")[0].members, ["", "b"])
        XCTAssertEqual(Phext.parseChains("\u{02}\u{02}")[0].members.count, 3)
        roundtrip("a\u{02}")
        roundtrip("\u{02}b")
        roundtrip("\u{02}\u{02}")
        roundtrip("\u{02}")

        let backToBack = Phext.parseChains("a\u{03}\u{03}")
        XCTAssertEqual(backToBack.count, 2)
        XCTAssertTrue(backToBack[0].closed && backToBack[1].closed)
        XCTAssertEqual(backToBack[1].members, [""])
        roundtrip("a\u{03}\u{03}")
    }

    func testSerializeFromConstructedChains() {
        var chain = Chain()
        XCTAssertFalse(chain.closed)
        XCTAssertEqual(chain.serialize(), "")
        chain.members.append("v1")
        chain.members.append("v2")
        XCTAssertEqual(chain.serialize(), "v1\u{02}v2")
        chain.closed = true
        XCTAssertEqual(chain.serialize(), "v1\u{02}v2\u{03}")
        XCTAssertEqual(Phext.serializeChains([chain]), "v1\u{02}v2\u{03}")
    }

    func testChainLayerDoesNotTouchMemberStructure() {
        let chains = Phext.parseChains("x\u{17}y\u{02}z\u{17}w\u{03}")
        XCTAssertEqual(chains[0].members, ["x\u{17}y", "z\u{17}w"])
        XCTAssertEqual(Phext.phokenize(chains[0].members[1]).count, 2)
        roundtrip("x\u{17}y\u{02}z\u{17}w\u{03}")
    }

    func testMultiverseAddressing() {
        let chain = Chain(members: ["U1 home", "U2 home"], closed: true)
        XCTAssertEqual(chain.fetch("1.1.1/1.1.1/1.1.1"), "U1 home")
        XCTAssertEqual(chain.fetch("$1:1.1.1/1.1.1/1.1.1"), "U1 home")
        XCTAssertEqual(chain.fetch("$2:1.1.1/1.1.1/1.1.1"), "U2 home")
        XCTAssertEqual(chain.fetch("$3:1.1.1/1.1.1/1.1.1"), "")
        XCTAssertNil(Phext.parseUniverseAddress("$0:1.1.1/1.1.1/1.1.1"))
        let parsed = Phext.parseUniverseAddress("$12:2.1.1/1.1.1/1.1.1")
        XCTAssertEqual(parsed?.0, 12)
        XCTAssertEqual(parsed?.1, Phext.toCoordinate("2.1.1/1.1.1/1.1.1"))
        // malformed prefixes yield "" from fetch, as rs does
        XCTAssertEqual(chain.fetch("$0:1.1.1/1.1.1/1.1.1"), "")
        XCTAssertEqual(chain.fetch("$x:1.1.1/1.1.1/1.1.1"), "")
        XCTAssertEqual(chain.fetch("$2"), "")
        XCTAssertEqual(chain.fetch("$:1.1.1/1.1.1/1.1.1"), "")
    }

    func testAdjacentClosesAreTwoEmptyChains() {
        let chains = Phext.parseChains("\u{03}\u{03}")
        XCTAssertEqual(chains.count, 2)
        XCTAssertTrue(chains.allSatisfy { $0.closed })
        XCTAssertEqual(Phext.serializeChains(chains), "\u{03}\u{03}")
    }
}
