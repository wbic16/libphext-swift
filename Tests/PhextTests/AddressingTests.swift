// AddressingTests.swift — ported 1:1 from libphext-rs 0.6.1
// src/test_address.rs.

import XCTest
@testable import Phext

final class AddressingTests: XCTestCase {
    private func home() -> Coordinate { Phext.toCoordinate("1.1.1/1.1.1/1.1.1") }
    private func scroll2() -> Coordinate { Phext.toCoordinate("1.1.1/1.1.1/1.1.2") }

    private func memberA() -> String {
        var member = Phext.insert("", home(), "alpha bravo\ncharlie delta\necho")
        member = Phext.insert(member, scroll2(), "second scroll\nline two")
        return member
    }

    private func memberB() -> String {
        Phext.insert("", home(), "uni2 home\nsecond line")
    }

    private func makeChain() -> Chain {
        Chain(members: [memberA(), memberB()], closed: false)
    }

    func testPointParseCanonical() {
        let p = Phext.parsePointAddress("$3:1.1.1/1.1.1/1.1.1@24,5")
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.universe, 3)
        XCTAssertEqual(p?.coordinate, home())
        XCTAssertEqual(p?.position, ScrollPosition(line: 24, column: 5))
        XCTAssertNil(p?.offset ?? nil)
        XCTAssertEqual(p?.description, "$3:1.1.1/1.1.1/1.1.1@24,5")
        // $1: is accepted on input, never emitted
        let p1 = Phext.parsePointAddress("$1:1.1.1/1.1.1/1.1.1@24,5")
        XCTAssertEqual(p1?.description, "1.1.1/1.1.1/1.1.1@24,5")
        // leading zeros parse by value; canonical form is minimal decimal
        let pz = Phext.parsePointAddress("1.1.1/1.1.1/1.1.1@024,005")
        XCTAssertEqual(pz?.description, "1.1.1/1.1.1/1.1.1@24,5")
        // bare coordinate: no position
        let bare = Phext.parsePointAddress("1.1.1/1.1.1/1.1.2")
        XCTAssertNotNil(bare)
        XCTAssertNil(bare?.position ?? nil)
        XCTAssertEqual(bare?.description, "1.1.1/1.1.1/1.1.2")
        // offset form
        let po = Phext.parsePointAddress("1.1.1/1.1.1/1.1.1@24,5+10")
        XCTAssertEqual(po?.offset, 10)
        XCTAssertEqual(po?.description, "1.1.1/1.1.1/1.1.1@24,5+10")
    }

    func testPointParseRejects() {
        for bad in [
            "$0:1.1.1/1.1.1/1.1.1@1,1",   // universe 0
            "1.1.1/1.1.1/1.1.1@0,5",      // line 0
            "1.1.1/1.1.1/1.1.1@24,0",     // column 0
            "1.1.1/1.1.1/0.1.1@1,1",      // coordinate component 0
            "1.1.1/1.1.1@1,1",            // only two arms
            "1.1.1/1.1.1/1.1.1@24",       // no column
            "1.1.1/1.1.1/1.1.1@24,5+",    // empty offset
            "1.1.1/1.1.1/1.1.1@24,+5",    // empty column
            "1.1.1/1.1.1/1.1.1@24,5@1,1", // second @
            "1.1.1/1.1.1/1.1.1@ 24,5",    // whitespace
            "",                            // empty
        ] {
            XCTAssertNil(Phext.parsePointAddress(bad), "expected rejection: \(bad.debugDescription)")
        }
    }

    func testPointResolve() {
        let c = makeChain()
        let p = Phext.parsePointAddress("1.1.1/1.1.1/1.1.1@2,3")!
        // line 1 "alpha bravo" = 11 chars + newline = 12; column 3 -> +2
        var resolved = c.resolvePoint(p)
        XCTAssertEqual(resolved?.0, 1)
        XCTAssertEqual(resolved?.1, home())
        XCTAssertEqual(resolved?.2, 14)
        // last valid boundary of line 1
        let end = Phext.parsePointAddress("1.1.1/1.1.1/1.1.1@1,12")!
        resolved = c.resolvePoint(end)
        XCTAssertEqual(resolved?.0, 1)
        XCTAssertEqual(resolved?.1, home())
        XCTAssertEqual(resolved?.2, 11)
        // past the line, past the scroll, missing scroll, missing universe
        XCTAssertNil(c.resolvePoint(Phext.parsePointAddress("1.1.1/1.1.1/1.1.1@1,13")!))
        XCTAssertNil(c.resolvePoint(Phext.parsePointAddress("1.1.1/1.1.1/1.1.1@4,1")!))
        XCTAssertNil(c.resolvePoint(Phext.parsePointAddress("1.1.1/1.1.1/1.1.9@1,1")!))
        XCTAssertNil(c.resolvePoint(Phext.parsePointAddress("$3:1.1.1/1.1.1/1.1.1@1,1")!))
        // bare point resolves to offset 0; universe 2 resolves in its own member
        resolved = c.resolvePoint(Phext.parsePointAddress("1.1.1/1.1.1/1.1.2")!)
        XCTAssertEqual(resolved?.0, 1)
        XCTAssertEqual(resolved?.1, scroll2())
        XCTAssertEqual(resolved?.2, 0)
        resolved = c.resolvePoint(Phext.parsePointAddress("$2:1.1.1/1.1.1/1.1.1@2,1")!)
        XCTAssertEqual(resolved?.0, 2)
        XCTAssertEqual(resolved?.1, home())
        XCTAssertEqual(resolved?.2, 10)
    }

    func testPointFetchOffset() {
        let c = makeChain()
        XCTAssertEqual(c.fetchPoint("1.1.1/1.1.1/1.1.1@1,1+5"), "alpha")
        XCTAssertEqual(c.fetchPoint("1.1.1/1.1.1/1.1.1@2,1+7"), "charlie")
        // across a line boundary: offset 9 is 'v' of "bravo"
        XCTAssertEqual(c.fetchPoint("1.1.1/1.1.1/1.1.1@1,10+5"), "vo\nch")
        // clipped at the scroll boundary, never into the next scroll
        XCTAssertEqual(c.fetchPoint("1.1.1/1.1.1/1.1.1@3,1+100"), "echo")
        XCTAssertEqual(c.fetchPoint("1.1.1/1.1.1/1.1.1@1,1+0"), "")
        // a bare point is a caret: fetches nothing; failures fetch nothing
        XCTAssertEqual(c.fetchPoint("1.1.1/1.1.1/1.1.1@1,1"), "")
        XCTAssertEqual(c.fetchPoint("1.1.1/1.1.1/1.1.1@9,1+3"), "")
        XCTAssertEqual(c.fetchPoint("$2:1.1.1/1.1.1/1.1.1@1,1+4"), "uni2")
    }

    func testPointFetchOffsetUnicode() {
        let member = Phext.insert("", home(), "héllo wörld")
        let c = Chain(members: [member], closed: false)
        // columns and offsets count scalars: é is one character (two bytes)
        let resolved = c.resolvePoint(Phext.parsePointAddress("1.1.1/1.1.1/1.1.1@1,3")!)
        XCTAssertEqual(resolved?.0, 1)
        XCTAssertEqual(resolved?.1, home())
        XCTAssertEqual(resolved?.2, 2)
        XCTAssertEqual(c.fetchPoint("1.1.1/1.1.1/1.1.1@1,2+3"), "éll")
    }

    func testRangeParseCanonical() {
        let r = Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1@24,5-1.1.1/1.1.1/1.1.1@24,9")
        XCTAssertEqual(r?.description, "1.1.1/1.1.1/1.1.1@24,5-1.1.1/1.1.1/1.1.1@24,9")
        // reversed input normalizes: direction is discarded
        let rev = Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1@24,9-1.1.1/1.1.1/1.1.1@24,5")
        XCTAssertEqual(rev, r)
        // $1: on input is dropped in canonical form, even beside a $3: endpoint
        let cross = Phext.parseRangeAddress("$1:1.1.1/1.1.1/1.1.1@24,5-$3:1.1.1/1.1.1/1.1.1@31,12")
        XCTAssertEqual(cross?.description, "1.1.1/1.1.1/1.1.1@24,5-$3:1.1.1/1.1.1/1.1.1@31,12")
        // offset forms are not range endpoints
        XCTAssertNil(Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1@1,1+3-1.1.1/1.1.1/1.1.1@1,5"))
        // one hyphen only
        XCTAssertNil(Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1-1.1.1/1.1.1/1.1.2-1.1.1/1.1.1/1.1.3"))
    }

    func testRangeFetchWithinScroll() {
        let c = makeChain()
        // characters 1-5 of line 1 (boundaries 1..6, half-open)
        XCTAssertEqual(c.fetchRange("1.1.1/1.1.1/1.1.1@1,1-1.1.1/1.1.1/1.1.1@1,6"), "alpha")
        // the whole of line 2, newline included
        XCTAssertEqual(c.fetchRange("1.1.1/1.1.1/1.1.1@2,1-1.1.1/1.1.1/1.1.1@3,1"), "charlie delta\n")
        // empty range is a caret
        XCTAssertEqual(c.fetchRange("1.1.1/1.1.1/1.1.1@1,3-1.1.1/1.1.1/1.1.1@1,3"), "")
        // reversed fetches the same extent
        XCTAssertEqual(c.fetchRange("1.1.1/1.1.1/1.1.1@1,6-1.1.1/1.1.1/1.1.1@1,1"), "alpha")
    }

    func testRangeFetchCrossScroll() {
        let c = makeChain()
        let frag = c.fetchRange("1.1.1/1.1.1/1.1.1@3,2-1.1.1/1.1.1/1.1.2@1,7")
        XCTAssertEqual(frag, "cho\u{17}second")
        // the fragment round-trips as a phext: its scrolls fetch back the segments
        let parsed = Phext.parseChains(frag)
        XCTAssertEqual(parsed[0].fetch("1.1.1/1.1.1/1.1.1"), "cho")
        XCTAssertEqual(parsed[0].fetch("1.1.1/1.1.1/1.1.2"), "second")
        // whole scrolls, no @ on either endpoint: the member itself
        XCTAssertEqual(c.fetchRange("1.1.1/1.1.1/1.1.1-1.1.1/1.1.1/1.1.2"), memberA())
    }

    func testRangeFetchMultiverse() {
        let c = makeChain()
        let frag = c.fetchRange("1.1.1/1.1.1/1.1.1@3,2-$2:1.1.1/1.1.1/1.1.1@1,5")
        // universe 1's scroll 2 lies strictly between the endpoints: a whole segment
        XCTAssertEqual(frag, "cho\u{17}second scroll\nline two\u{2}uni2")
        let parsed = Phext.parseChains(frag)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].members.count, 2)
        XCTAssertEqual(parsed[0].fetch("$2:1.1.1/1.1.1/1.1.1"), "uni2")
        // resolve_range exposes the segments
        let range = Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1@3,2-$2:1.1.1/1.1.1/1.1.1@1,5")!
        let segments = c.resolveRange(range)
        XCTAssertNotNil(segments)
        XCTAssertEqual(segments?.count, 3)
        XCTAssertEqual(segments?[0].0, 1)
        XCTAssertEqual(segments?[0].1, home())
        XCTAssertEqual(segments?[0].2, "cho")
        XCTAssertEqual(segments?[1].0, 1)
        XCTAssertEqual(segments?[1].1, scroll2())
        XCTAssertEqual(segments?[1].2, "second scroll\nline two")
        XCTAssertEqual(segments?[2].0, 2)
        XCTAssertEqual(segments?[2].1, home())
        XCTAssertEqual(segments?[2].2, "uni2")
    }

    func testRangeResolutionErrors() {
        let c = makeChain()
        // universe past the end of the chain
        XCTAssertEqual(c.fetchRange("1.1.1/1.1.1/1.1.1@1,1-$3:1.1.1/1.1.1/1.1.1@1,1"), "")
        XCTAssertNil(c.resolveRange(Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1@1,1-$3:1.1.1/1.1.1/1.1.1@1,1")!))
        // missing endpoint scroll
        XCTAssertNil(c.resolveRange(Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1@1,1-1.1.1/1.1.1/1.1.9@1,1")!))
        // line past the scroll's end: an error, never a clamp
        XCTAssertNil(c.resolveRange(Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1@1,1-1.1.1/1.1.1/1.1.1@9,1")!))
        // column past the line's last boundary
        XCTAssertNil(c.resolveRange(Phext.parseRangeAddress("1.1.1/1.1.1/1.1.1@1,1-1.1.1/1.1.1/1.1.1@1,13")!))
    }
}
