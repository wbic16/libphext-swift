// ChainFixtureTests.swift — consumes the shared libphext 0.6 chain
// conformance fixtures (tests/fixtures/chains, copied from libphext-rs;
// format: FIXTURES.md in the fixture set). For every case: input length
// + sha256, chain structure (closed flags, member bytes + sha256, the
// phokenize scroll list per member from manifest.json), byte-identical
// round-trip, and every fetch compared byte-for-byte with its expected
// file. One XCTest method per case so failures are reported per case.

import Foundation
import XCTest
@testable import Phext

final class ChainFixtureTests: XCTestCase {
    private var fixturesRoot: URL {
        // Tests/PhextTests/ChainFixtureTests.swift -> package root
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent() // PhextTests
            .appendingPathComponent("Fixtures/chains")
    }

    private struct Manifest: Decodable {
        struct Scroll: Decodable { let c: String; let b: Int; let s: String }
        struct Member: Decodable { let bytes: Int; let sha256: String; let scrolls: [Scroll] }
        struct ChainEntry: Decodable { let closed: Bool; let members: [Member] }
        struct Fetch: Decodable {
            let chain_index: Int
            let address: String
            let expected_file: String
        }
        let input_bytes: Int
        let input_sha256: String
        let chains: [ChainEntry]
        let fetches: [Fetch]
    }

    private func runCase(_ name: String) throws {
        let caseDir = fixturesRoot.appendingPathComponent(name)
        let manifestData = try Data(contentsOf: caseDir.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

        // 1. input bytes + hash
        let inputData = try Data(contentsOf: caseDir.appendingPathComponent("input.phext"))
        let inputBytes = [UInt8](inputData)
        XCTAssertEqual(inputBytes.count, manifest.input_bytes, "\(name): input length")
        XCTAssertEqual(SHA256.hexDigest(inputBytes), manifest.input_sha256, "\(name): input sha256")
        let input = String(decoding: inputBytes, as: UTF8.self)
        XCTAssertEqual([UInt8](input.utf8), inputBytes, "\(name): input must be valid UTF-8 phext text")

        // 2. structure
        let chains = Phext.parseChains(input)
        XCTAssertEqual(chains.count, manifest.chains.count, "\(name): chain count")
        for (chainIndex, expectedChain) in manifest.chains.enumerated() {
            guard chainIndex < chains.count else { break }
            let chain = chains[chainIndex]
            XCTAssertEqual(chain.closed, expectedChain.closed, "\(name): chain \(chainIndex) closed")
            XCTAssertEqual(chain.members.count, expectedChain.members.count, "\(name): chain \(chainIndex) member count")
            for (memberIndex, expectedMember) in expectedChain.members.enumerated() {
                guard memberIndex < chain.members.count else { break }
                let memberBytes = [UInt8](chain.members[memberIndex].utf8)
                XCTAssertEqual(memberBytes.count, expectedMember.bytes, "\(name): member \(chainIndex)/\(memberIndex) bytes")
                XCTAssertEqual(SHA256.hexDigest(memberBytes), expectedMember.sha256, "\(name): member \(chainIndex)/\(memberIndex) sha256")
                let scrolls = Phext.phokenize(chain.members[memberIndex])
                XCTAssertEqual(scrolls.count, expectedMember.scrolls.count, "\(name): member \(chainIndex)/\(memberIndex) scroll count")
                for (scrollIndex, expectedScroll) in expectedMember.scrolls.enumerated() {
                    guard scrollIndex < scrolls.count else { break }
                    let scroll = scrolls[scrollIndex]
                    XCTAssertEqual(scroll.coord.toString(), expectedScroll.c, "\(name): scroll \(chainIndex)/\(memberIndex)/\(scrollIndex) coordinate")
                    XCTAssertEqual(scroll.scroll.utf8.count, expectedScroll.b, "\(name): scroll \(chainIndex)/\(memberIndex)/\(scrollIndex) bytes")
                    XCTAssertEqual(SHA256.hexDigest([UInt8](scroll.scroll.utf8)), expectedScroll.s, "\(name): scroll \(chainIndex)/\(memberIndex)/\(scrollIndex) sha256")
                }
            }
        }

        // 3. byte-identical round-trip
        XCTAssertEqual([UInt8](Phext.serializeChains(chains).utf8), inputBytes, "\(name): round-trip must be byte-identical")

        // 4. fetches, byte-for-byte
        for fetch in manifest.fetches {
            let expectedData = try Data(contentsOf: caseDir.appendingPathComponent(fetch.expected_file))
            guard fetch.chain_index < chains.count else {
                XCTFail("\(name): fetch chain_index out of range")
                continue
            }
            let result = chains[fetch.chain_index].fetch(fetch.address)
            XCTAssertEqual([UInt8](result.utf8), [UInt8](expectedData), "\(name): fetch \(fetch.address)")
        }
    }

    func testFixtureSingleMember() throws { try runCase("single-member") }
    func testFixtureMultiMember3() throws { try runCase("multi-member-3") }
    func testFixtureUnclosedAtEOF() throws { try runCase("unclosed-at-eof") }
    func testFixtureAdjacentChainCloses() throws { try runCase("adjacent-chain-closes") }
    func testFixtureEmptyMember() throws { try runCase("empty-member") }
    func testFixtureChainOfOneEmptyPhext() throws { try runCase("chain-of-one-empty-phext") }
    func testFixtureEmptyStream() throws { try runCase("empty-stream") }
    func testFixtureMultipleChains() throws { try runCase("multiple-chains") }
    func testFixtureRealCorporaChain() throws { try runCase("real-corpora-chain") }
    func testFixtureMultiverseAddressing() throws { try runCase("multiverse-addressing") }

    func testSHA256HelperSanity() {
        // FIPS 180-4 example vector, so a broken helper can't fake passes
        XCTAssertEqual(SHA256.hexDigest([UInt8]("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hexDigest([]),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
