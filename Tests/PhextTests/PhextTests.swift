// PhextTests.swift — ported from libphext-rs 0.6.0 src/test_lib.rs
// (a representative 1:1 selection covering every public operation) and
// src/test_phokenize.rs.

import XCTest
@testable import Phext

final class PhextTests: XCTestCase {
    private func coord(_ s: String) -> Coordinate { Phext.toCoordinate(s) }

    func testCoordinateParsing() {
        let c = Phext.toCoordinate("2.7.1/3.9.4/5.2.8")
        XCTAssertEqual(c.z.library, 2); XCTAssertEqual(c.z.shelf, 7); XCTAssertEqual(c.z.series, 1)
        XCTAssertEqual(c.y.collection, 3); XCTAssertEqual(c.y.volume, 9); XCTAssertEqual(c.y.book, 4)
        XCTAssertEqual(c.x.chapter, 5); XCTAssertEqual(c.x.section, 2); XCTAssertEqual(c.x.scroll, 8)
        XCTAssertEqual(c.toString(), "2.7.1/3.9.4/5.2.8")
        XCTAssertEqual(Coordinate().toString(), "1.1.1/1.1.1/1.1.1")
    }

    func testToUrlEncoded() {
        XCTAssertEqual(coord("1.1.1/1.1.1/1.1.1").toUrlEncoded(), "1.1.1;1.1.1;1.1.1")
        XCTAssertEqual(coord("2.7.1/3.9.4/5.2.8").toUrlEncoded(), "2.7.1;3.9.4;5.2.8")
        // ';' is an accepted macro delimiter on parse, as in rs
        XCTAssertEqual(Phext.toCoordinate("2.7.1;3.9.4;5.2.8"), coord("2.7.1/3.9.4/5.2.8"))
    }

    func testStrictParseValidRoundTrips() throws {
        for address in ["1.1.1/1.1.1/1.1.1", "2.7.1/3.9.4/5.2.8", "1000.2000.3000/1.1.1/1.1.1", "1.1.1/1.1.1/1.1.18446744073709551615"] {
            let parsed = try Coordinate.parse(address)
            XCTAssertEqual(parsed.toString(), address)
        }
        // leading '+' spellings are accepted by Rust's usize parser
        XCTAssertEqual(try Coordinate.parse("+1.1.1/1.1.1/1.1.1").toString(), "1.1.1/1.1.1/1.1.1")
    }

    func testStrictParseMalformedReturnsError() {
        for bad in ["", "1.1/1.1.1/1.1.1", "1.1.1/1.1.1", "1.1.1/1.1.1/1.1.1/1", "a.1.1/1.1.1/1.1.1",
                    "1.1.1/1.1.1/1.1.-1", "1.1.1/1.1.1/1.1.", "1.1.1/1.1.1/1.1. 1", "1.1.1/1.1.1/99999999999999999999999999",
                    "1.1.1;1.1.1;1.1.1", "1,1,1/1,1,1/1,1,1"] {
            XCTAssertThrowsError(try Coordinate.parse(bad), "expected error for \(bad)")
        }
    }

    func testToCoordinateLongDigitRunSaturates() {
        let c = Phext.toCoordinate("1.1.1/1.1.1/1.1.99999999999999999999999999999")
        XCTAssertEqual(c.x.scroll, UInt64.max)
    }

    func testValidateCoordinate() {
        XCTAssertTrue(Coordinate().validateCoordinate())
        XCTAssertFalse(Coordinate(0, 1, 1, 1, 1, 1, 1, 1, 1).validateCoordinate())
        XCTAssertEqual(Coordinate(0, 1, 1, 1, 1, 1, 1, 1, 1).toString(), "")
    }

    func testFetchAcrossDimensions() {
        // mirrors rs test_scrolls..test_libraries via the shared doc shape
        let doc = "first scroll\u{17}second scroll\u{18}second section\u{19}second chapter\u{1A}book 2\u{1C}volume 2\u{1D}collection 2\u{1E}series 2\u{1F}shelf 2\u{01}library 2"
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.1")), "first scroll")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.2")), "second scroll")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.2.1")), "second section")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/2.1.1")), "second chapter")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.2/1.1.1")), "book 2")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.2.1/1.1.1")), "volume 2")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/2.1.1/1.1.1")), "collection 2")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.2/1.1.1/1.1.1")), "series 2")
        XCTAssertEqual(Phext.fetch(doc, coord("1.2.1/1.1.1/1.1.1")), "shelf 2")
        XCTAssertEqual(Phext.fetch(doc, coord("2.1.1/1.1.1/1.1.1")), "library 2")
        XCTAssertEqual(Phext.fetch(doc, coord("9.9.9/9.9.9/9.9.9")), "")
        XCTAssertEqual(Phext.fetch("", coord("1.1.1/1.1.1/1.1.1")), "")
    }

    func testLineBreakStaysInsideScroll() {
        let doc = "line one\nline two\u{17}next"
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.1")), "line one\nline two")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.2")), "next")
    }

    func testMoreCowbell() {
        XCTAssertTrue(Phext.checkForCowbell("ding\u{07}"))
        XCTAssertFalse(Phext.checkForCowbell("no bell"))
    }

    func testInsert() {
        var doc = Phext.insert("", coord("1.1.1/1.1.1/1.1.1"), "Hello")
        XCTAssertEqual(doc, "Hello")
        doc = Phext.insert(doc, coord("1.1.1/1.1.1/1.1.2"), "World")
        XCTAssertEqual(doc, "Hello\u{17}World")
        doc = Phext.insert(doc, coord("1.1.1/1.1.1/1.1.1"), "Again ")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.1")), "HelloAgain ")
        // insert far away materializes the break ladder
        let far = Phext.insert("", coord("2.1.1/1.1.1/1.1.1"), "far")
        XCTAssertEqual(far, "\u{01}far")
        XCTAssertEqual(Phext.fetch(far, coord("2.1.1/1.1.1/1.1.1")), "far")
    }

    func testReplace() {
        var doc = Phext.replace("", coord("1.1.1/1.1.1/1.1.1"), "alpha")
        doc = Phext.replace(doc, coord("1.1.1/1.1.1/1.1.2"), "beta")
        XCTAssertEqual(doc, "alpha\u{17}beta")
        doc = Phext.replace(doc, coord("1.1.1/1.1.1/1.1.1"), "ALPHA")
        XCTAssertEqual(doc, "ALPHA\u{17}beta")
        // replace creating a scroll between two existing ones acts on the
        // right scroll, not the one before it (rs get_subspace fix)
        doc = Phext.replace(doc, coord("1.1.1/1.1.1/1.2.1"), "section")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.2.1")), "section")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.2")), "beta")
    }

    func testRemove() {
        let doc = "one\u{17}two\u{17}three"
        let removed = Phext.remove(doc, coord("1.1.1/1.1.1/1.1.2"))
        XCTAssertEqual(Phext.fetch(removed, coord("1.1.1/1.1.1/1.1.2")), "")
        XCTAssertEqual(Phext.fetch(removed, coord("1.1.1/1.1.1/1.1.1")), "one")
        XCTAssertEqual(Phext.fetch(removed, coord("1.1.1/1.1.1/1.1.3")), "three")
    }

    func testRangeReplace() {
        let doc = "one\u{17}two\u{17}three"
        let range = PhextRange(start: coord("1.1.1/1.1.1/1.1.1"), end: coord("1.1.1/1.1.1/1.1.2"))
        XCTAssertEqual(Phext.rangeReplace(doc, range, "X"), "X\u{17}three")
    }

    func testNextScroll() {
        let doc = "3A\u{17}B2\u{18}C1"
        let (update, nextStart, remaining) = Phext.nextScroll(doc, coord("1.1.1/1.1.1/1.1.1"))
        XCTAssertEqual(update.coord.toString(), "1.1.1/1.1.1/1.1.1")
        XCTAssertEqual(update.scroll, "3A")
        XCTAssertEqual(nextStart.toString(), "1.1.1/1.1.1/1.1.2")
        XCTAssertEqual(remaining, "B2\u{18}C1")
    }

    func testPhokenize() {
        let doc1 = "one\u{17}two\u{17}three\u{17}four"
        XCTAssertEqual(Phext.phokenize(doc1), [
            PositionedScroll(coord: coord("1.1.1/1.1.1/1.1.1"), scroll: "one"),
            PositionedScroll(coord: coord("1.1.1/1.1.1/1.1.2"), scroll: "two"),
            PositionedScroll(coord: coord("1.1.1/1.1.1/1.1.3"), scroll: "three"),
            PositionedScroll(coord: coord("1.1.1/1.1.1/1.1.4"), scroll: "four"),
        ])
        let doc2 = "one\u{01}two\u{1F}three\u{1E}four\u{1D}five\u{1C}six\u{1A}seven\u{19}eight\u{18}nine\u{17}ten"
        let update2 = Phext.phokenize(doc2)
        XCTAssertEqual(update2.map { $0.coord.toString() }, [
            "1.1.1/1.1.1/1.1.1", "2.1.1/1.1.1/1.1.1", "2.2.1/1.1.1/1.1.1", "2.2.2/1.1.1/1.1.1",
            "2.2.2/2.1.1/1.1.1", "2.2.2/2.2.1/1.1.1", "2.2.2/2.2.2/1.1.1", "2.2.2/2.2.2/2.1.1",
            "2.2.2/2.2.2/2.2.1", "2.2.2/2.2.2/2.2.2",
        ])
        XCTAssertEqual(update2.map { $0.scroll }, ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"])
        // leading breaks are skipped; the single token lands at its walked coordinate
        let doc4 = "\u{1A}\u{1C}\u{1D}\u{1E}\u{1F}\u{01}stuff here"
        XCTAssertEqual(Phext.phokenize(doc4), [PositionedScroll(coord: coord("2.1.1/1.1.1/1.1.1"), scroll: "stuff here")])
        // the empty document phokenizes to one empty scroll at home
        XCTAssertEqual(Phext.phokenize(""), [PositionedScroll(coord: coord("1.1.1/1.1.1/1.1.1"), scroll: "")])
    }

    func testLastEmptyScroll() {
        let doc = "hello\u{17}world\u{17}"
        let target = coord("1.1.1/1.1.1/1.1.2")
        let parts = Phext.getSubspaceCoordinates([UInt8](doc.utf8), target)
        XCTAssertEqual(parts.0, 6)
        XCTAssertEqual(parts.1, 11)
        XCTAssertEqual(parts.2, target)
        XCTAssertEqual(Phext.fetch(doc, target), "world")
    }

    func testExplodeImplode() {
        let doc = "one\u{17}two\u{18}three"
        let map = Phext.explode(doc)
        XCTAssertEqual(map[coord("1.1.1/1.1.1/1.1.1")], "one")
        XCTAssertEqual(map[coord("1.1.1/1.1.1/1.1.2")], "two")
        XCTAssertEqual(map[coord("1.1.1/1.1.1/1.2.1")], "three")
        XCTAssertEqual(Phext.implode(map), doc)
    }

    func testMerge() {
        XCTAssertEqual(Phext.merge("3A\u{17}B2", "4C\u{17}D1"), "3A4C\u{17}B2D1")
        XCTAssertEqual(
            Phext.merge("Hello \u{17}I've come to talk", "Darkness, my old friend.\u{17} with you again."),
            "Hello Darkness, my old friend.\u{17}I've come to talk with you again.")
        XCTAssertEqual(Phext.merge("AA\u{01}BB\u{01}CC", "__\u{01}__\u{01}__"), "AA__\u{01}BB__\u{01}CC__")
    }

    func testSubtract() {
        XCTAssertEqual(
            Phext.subtract("Here's scroll one.\u{17}Scroll two.", "Just content at the first scroll"),
            "\u{17}Scroll two.")
    }

    func testNormalize() {
        XCTAssertEqual(Phext.normalize("\u{17}Scroll two\u{18}\u{18}\u{18}\u{18}"), "\u{17}Scroll two")
    }

    func testExpandContract() {
        XCTAssertEqual(Phext.expand("a\nb"), "a\u{17}b")
        XCTAssertEqual(Phext.expand("a\u{17}b"), "a\u{18}b")
        XCTAssertEqual(Phext.contract("a\u{17}b"), "a\nb")
        XCTAssertEqual(Phext.contract(Phext.expand("a\nb\u{17}c")), "a\nb\u{17}c")
    }

    func testSummaryNavmapTextmap() {
        XCTAssertEqual(Phext.createSummary("hello\u{17}world"), "hello...")
        XCTAssertEqual(Phext.createSummary("hello"), "hello")
        XCTAssertEqual(Phext.createSummary("line\nbreak"), "line...")
        let doc = "alpha\u{17}beta"
        XCTAssertEqual(Phext.textmap(doc), "* 1.1.1/1.1.1/1.1.1: alpha\n* 1.1.1/1.1.1/1.1.2: beta\n")
        XCTAssertEqual(
            Phext.navmap("?coord=", doc),
            "<ul>\n<li><a href=\"?coord=1.1.1;1.1.1;1.1.1\">1.1.1/1.1.1/1.1.1 alpha</a></li>\n<li><a href=\"?coord=1.1.1;1.1.1;1.1.2\">1.1.1/1.1.1/1.1.2 beta</a></li>\n</ul>\n")
    }

    func testIndexAndOffset() {
        let doc = "one\u{17}two\u{18}three"
        let indexed = Phext.index(doc)
        XCTAssertEqual(Phext.fetch(indexed, coord("1.1.1/1.1.1/1.1.1")), "0")
        XCTAssertEqual(Phext.offset(doc, coord("1.1.1/1.1.1/1.1.1")), 0)
        XCTAssertEqual(Phext.offset(doc, coord("1.1.1/1.1.1/1.1.2")), 4)
        XCTAssertEqual(Phext.offset(doc, coord("1.1.1/1.1.1/1.2.1")), 8)
        XCTAssertEqual(Phext.offset("", coord("1.1.1/1.1.1/1.1.1")), 0)
    }

    func testChecksumVectors() {
        // rs test_lib.rs::test_scroll_manifest vectors (xxh3-128)
        XCTAssertEqual(Phext.checksum("00000000000000000000"), "7e79edd92a62a048e1cd24ffab542e34")
        XCTAssertEqual(Phext.checksum("first scroll"), "ba9d944e4967e29d48bae69ac2999699")
        XCTAssertEqual(Phext.checksum("second scroll"), "2fe1b2040314ac66f132dd3b4926157c")
        XCTAssertEqual(Phext.checksum("book 2"), "0f20f79bf36f63e8fba25cc6765e2d0d")
    }

    func testManifest() {
        let example = "first scroll\u{17}second scroll\u{18}second section\u{19}second chapter\u{1A}book 2\u{1C}volume 2\u{1D}collection 2\u{1E}series 2\u{1F}shelf 2\u{01}library 2"
        let expected = "ba9d944e4967e29d48bae69ac2999699\u{17}2fe1b2040314ac66f132dd3b4926157c\u{18}fddb6916753b6f4e0b5281469134778b\u{19}16ab5b1a0a997db95ec215a3bf2c57b3\u{1A}0f20f79bf36f63e8fba25cc6765e2d0d\u{1C}7ead0c6fef43adb446fe3bda6fb0adc7\u{1D}78c12298931c6edede92962137a9280a\u{1E}0f35100c84df601a490b7b63d7e8c0a8\u{1F}3bbf7e67cb33d613a906bc5a3cbefd95\u{01}2e7fdd387196a8a2706ccb9ad6792bc3"
        XCTAssertEqual(Phext.manifest(example), expected)
    }

    func testSoundexV1() {
        let sample = "it was the best of scrolls\u{17}it was the worst of scrolls\u{17}aaa\u{17}bbb\u{17}ccc\u{17}ddd\u{17}eee\u{17}fff\u{17}ggg\u{17}hhh\u{17}iii\u{17}jjj\u{17}kkk\u{17}lll\u{18}mmm\u{18}nnn\u{18}ooo\u{18}ppp\u{19}qqq\u{19}rrr\u{19}sss\u{19}ttt\u{1A}uuu\u{1A}vvv\u{1A}www\u{1A}xxx\u{1A}yyy\u{1A}zzz"
        XCTAssertEqual(
            Phext.soundexV1(sample),
            "36\u{17}41\u{17}1\u{17}4\u{17}7\u{17}10\u{17}1\u{17}4\u{17}7\u{17}1\u{17}1\u{17}7\u{17}7\u{17}13\u{18}16\u{18}16\u{18}1\u{18}4\u{19}7\u{19}19\u{19}7\u{19}10\u{1A}1\u{1A}4\u{1A}1\u{1A}7\u{1A}1\u{1A}7")
    }

    func testUnboundedCoordinates() {
        // above-999 components parse, print, fetch, and advance (rs 0.4.0+)
        let c = try! Coordinate.parse("1000.1.1/1.1.1/1.1.1")
        XCTAssertEqual(c.toString(), "1000.1.1/1.1.1/1.1.1")
        var doc = ""
        doc = Phext.insert(doc, coord("1.1.1/1.1.1/1.1.1001"), "deep")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.1001")), "deep")
        var walker = coord("1.1.1/1.1.1/1.1.999")
        walker.scrollBreak()
        XCTAssertEqual(walker.x.scroll, 1000)
    }

    func testEmojiInScroll() {
        let doc = Phext.insert("", coord("1.1.1/1.1.1/1.1.1"), "scroll 🚀 emoji")
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.1")), "scroll 🚀 emoji")
        let doc2 = Phext.insert(doc, coord("1.1.1/1.1.1/1.1.2"), "second ✓")
        XCTAssertEqual(Phext.fetch(doc2, coord("1.1.1/1.1.1/1.1.2")), "second ✓")
        XCTAssertEqual(Phext.fetch(doc2, coord("1.1.1/1.1.1/1.1.1")), "scroll 🚀 emoji")
    }

    func testIsPhextBreak() {
        XCTAssertTrue(Phext.isPhextBreak(0x0A))
        XCTAssertTrue(Phext.isPhextBreak(0x17))
        XCTAssertTrue(Phext.isPhextBreak(0x01))
        XCTAssertFalse(Phext.isPhextBreak(0x02))
        XCTAssertFalse(Phext.isPhextBreak(0x41))
    }
}
