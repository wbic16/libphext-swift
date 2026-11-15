// SealTests.swift — ported 1:1 from libphext-rs 0.6.0 src/test_seal.rs,
// plus the byte-identity pin: liblzma at preset 6 + CRC64 produces the
// same sealed bytes in every port (the C leg verified this vs rs).

import XCTest
@testable import Phext

final class SealTests: XCTestCase {
    func testSealRoundTripRealPhext() throws {
        // a real, multi-scroll phext built through the library itself
        var corpus = Phext.insert("", Phext.toCoordinate("1.1.1/1.1.1/1.1.1"), "Welcome to phext")
        corpus = Phext.insert(corpus, Phext.toCoordinate("1.1.1/1.1.1/1.1.2"), "second scroll ✓")
        corpus = Phext.insert(corpus, Phext.toCoordinate("2.1.1/1.3.1/2.1.1"), "far away")
        let sealed = try PhextSeal.seal(corpus)
        XCTAssertFalse(sealed.isEmpty)
        XCTAssertEqual(Array(sealed[0..<6]), [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) // xz magic
        XCTAssertEqual(try PhextSeal.unsealString(sealed), corpus)
    }

    func testSealRoundTripEmptyAndSmall() throws {
        XCTAssertEqual(try PhextSeal.unsealString(try PhextSeal.seal("")), "")
        XCTAssertEqual(try PhextSeal.unseal(try PhextSeal.seal("hello phext")), [UInt8]("hello phext".utf8))
    }

    func testSealCarryingBinaryScrolls() throws {
        let doc = "cover text\u{17}phext-binary:1:base64\nAAEC/f7/fw==\u{17}after"
        XCTAssertEqual(try PhextSeal.unsealString(try PhextSeal.seal(doc)), doc)
    }

    func testSealIsDeterministic() throws {
        let doc = "the same phext, sealed twice\u{17}the same phext, sealed twice"
        XCTAssertEqual(try PhextSeal.seal(doc), try PhextSeal.seal(doc))
    }

    func testUnsealRejectsNonXZData() {
        XCTAssertThrowsError(try PhextSeal.unseal([UInt8]("this is not an xz stream".utf8)))
        XCTAssertThrowsError(try PhextSeal.unseal([]))
        XCTAssertThrowsError(try PhextSeal.unsealString([UInt8]("phext, but unsealed".utf8)))
    }

    func testSealPreset() {
        XCTAssertEqual(PhextSeal.sealPreset, 6)
    }
}
