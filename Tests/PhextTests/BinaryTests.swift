// BinaryTests.swift — ported 1:1 from libphext-rs 0.6.0 src/test_binary.rs.

import XCTest
@testable import Phext

final class BinaryTests: XCTestCase {
    private func coord(_ s: String) -> Coordinate { Phext.toCoordinate(s) }

    func testEncodeDecodeRoundTrip() {
        let empty: [UInt8] = []
        let emptyScroll = PhextBinary.encodeScroll(empty)
        XCTAssertEqual(emptyScroll, "phext-binary:1:base64\n")
        XCTAssertEqual(PhextBinary.decodeScroll(emptyScroll), empty)

        let allBytes: [UInt8] = (0...255).map { UInt8($0) }
        let scroll = PhextBinary.encodeScroll(allBytes)
        XCTAssertTrue(PhextBinary.isBinaryScroll(scroll))
        XCTAssertEqual(PhextBinary.decodeScroll(scroll), allBytes)

        let foreign: [UInt8] = [0xFF, 0xFE, 0x80, 0x00, 0x61, 0xC3, 0x28]
        XCTAssertEqual(PhextBinary.decodeScroll(PhextBinary.encodeScroll(foreign)), foreign)

        let big: [UInt8] = (0..<(1024 * 1024 + 13)).map { UInt8($0 % 256) }
        XCTAssertEqual(PhextBinary.decodeScroll(PhextBinary.encodeScroll(big)), big)
    }

    func testDecodeScrollRejectsNonBinary() {
        XCTAssertNil(PhextBinary.decodeScroll("just some text"))
        XCTAssertNil(PhextBinary.decodeScroll(""))
        XCTAssertNil(PhextBinary.decodeScroll("phext-binary:1:base64"))
        XCTAssertFalse(PhextBinary.isBinaryScroll("phext-binary:1:base64"))
        let malformed = "phext-binary:1:base64\n!!! not base64 !!!"
        XCTAssertTrue(PhextBinary.isBinaryScroll(malformed))
        XCTAssertNil(PhextBinary.decodeScroll(malformed))
        // strictness pins vs Foundation's default decoder: whitespace and
        // missing padding are not canonical base64
        XCTAssertNil(PhextBinary.decodeScroll("phext-binary:1:base64\nQUJD RA=="))
        XCTAssertNil(PhextBinary.decodeScroll("phext-binary:1:base64\nQUI"))
        XCTAssertNil(PhextBinary.decodeScroll("phext-binary:1:base64\nQUJD\n"))
    }

    func testInsertAndFetchBinary() {
        let target = coord("1.1.1/1.1.1/1.1.2")
        let payload: [UInt8] = [0x00, 0x01, 0x02, 0xFE, 0xFF, 0x7F, 0x80]
        var doc = Phext.insert("", coord("1.1.1/1.1.1/1.1.1"), "plain text scroll")
        doc = PhextBinary.insertBinary(doc, target, payload)
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.1")), "plain text scroll")
        XCTAssertEqual(PhextBinary.fetchBinary(doc, target), payload)
        let stored = Phext.fetch(doc, target)
        XCTAssertTrue(PhextBinary.isBinaryScroll(stored))
        XCTAssertEqual(PhextBinary.decodeScroll(stored), payload)
    }

    func testFetchBinaryFallbacks() {
        let doc = Phext.insert("", coord("1.1.1/1.1.1/1.1.1"), "hello")
        XCTAssertEqual(PhextBinary.fetchBinary(doc, coord("1.1.1/1.1.1/1.1.1")), [UInt8]("hello".utf8))
        XCTAssertEqual(PhextBinary.fetchBinary(doc, coord("9.9.9/9.9.9/9.9.9")), [])
        let malformed = Phext.insert("", coord("1.1.1/1.1.1/1.1.1"), "phext-binary:1:base64\n!!!")
        XCTAssertEqual(PhextBinary.fetchBinary(malformed, coord("1.1.1/1.1.1/1.1.1")), [UInt8]("phext-binary:1:base64\n!!!".utf8))
    }

    func testReplaceBinary() {
        let target = coord("1.1.1/1.1.1/1.1.1")
        let doc = PhextBinary.replaceBinary("old", target, [0xDE, 0xAD])
        XCTAssertEqual(PhextBinary.fetchBinary(doc, target), [0xDE, 0xAD])
    }

    func testUpdateRuleNonUTF8IsBase64Verbatim() {
        let target = coord("1.1.1/1.1.1/1.1.1")
        let payload: [UInt8] = [0xFF, 0x17, 0x1C, 0x80, 0x00]
        let doc = PhextBinary.replaceBytes("", target, payload)
        let stored = Phext.fetch(doc, target)
        XCTAssertTrue(PhextBinary.isBinaryScroll(stored))
        XCTAssertEqual(PhextBinary.fetchBinary(doc, target), payload)
        let doc2 = PhextBinary.insertBytes("", target, payload)
        XCTAssertEqual(PhextBinary.fetchBinary(doc2, target), payload)
    }

    func testUpdateRuleUTF8StaysText() {
        let target = coord("1.1.1/1.1.1/1.1.1")
        let doc = PhextBinary.replaceBytes("", target, [UInt8]("ordinary text ✓".utf8))
        XCTAssertEqual(Phext.fetch(doc, target), "ordinary text ✓")
        XCTAssertFalse(PhextBinary.isBinaryScroll(Phext.fetch(doc, target)))
        XCTAssertEqual(PhextBinary.fetchBinary(doc, target), [UInt8]("ordinary text ✓".utf8))
    }

    func testIngestForeignByteStream() {
        var stream: [UInt8] = [UInt8]("hello".utf8)
        stream.append(Phext.scrollBreakU8)
        stream.append(contentsOf: [0xFF, 0xFE, 0x41, 0x80])
        let doc = PhextBinary.ingest(stream)
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.1")), "hello")
        let foreignAt = coord("1.1.1/1.1.1/1.1.2")
        XCTAssertTrue(PhextBinary.isBinaryScroll(Phext.fetch(doc, foreignAt)))
        XCTAssertEqual(PhextBinary.fetchBinary(doc, foreignAt), [0xFF, 0xFE, 0x41, 0x80])
    }

    func testIngestCanonicalPhextIsIdentity() {
        var doc = Phext.insert("", coord("1.1.1/1.1.1/1.1.1"), "first")
        doc = Phext.insert(doc, coord("1.1.1/1.1.1/1.1.2"), "second ✓ scroll")
        doc = Phext.insert(doc, coord("2.1.1/1.3.1/1.1.1"), "far away")
        XCTAssertEqual(PhextBinary.ingest([UInt8](doc.utf8)), doc)
    }

    func testIngestEmptyAndBreakOnlyStreams() {
        XCTAssertEqual(Phext.fetch(PhextBinary.ingest([]), coord("1.1.1/1.1.1/1.1.1")), "")
        let doc = PhextBinary.ingest([Phext.scrollBreakU8, Phext.sectionBreakU8])
        XCTAssertEqual(Phext.fetch(doc, coord("1.1.1/1.1.1/1.1.1")), "")
    }

    func testPhokenizeBytesMatchesPhokenize() {
        let doc = "alpha\u{17}beta\u{18}gamma"
        let textParts = Phext.phokenize(doc)
        let byteParts = PhextBinary.phokenizeBytes([UInt8](doc.utf8))
        XCTAssertEqual(textParts.count, byteParts.count)
        for (textPart, bytePart) in zip(textParts, byteParts) {
            XCTAssertEqual(textPart.coord, bytePart.0)
            XCTAssertEqual([UInt8](textPart.scroll.utf8), bytePart.1)
        }
    }
}
