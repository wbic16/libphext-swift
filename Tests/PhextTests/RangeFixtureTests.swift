// RangeFixtureTests.swift — consumes the shared libphext 0.6.1 range
// conformance fixtures (Tests/PhextTests/Fixtures/ranges, copied from
// libphext-rs tests/fixtures/ranges; format: FIXTURES-RANGES.md in the
// ports program workspace). For every case: input length + sha256, then
// every op in expected.tsv run against chain 0 of parseChains(input) —
// parse_point / parse_range canonical forms and rejections,
// resolve_point tuples, and fetch_point / fetch_range result bytes
// compared byte-for-byte with results/NN.txt, with the recorded
// `resolved` flag checked against resolve_point / resolve_range so the
// resolved-but-empty and unresolved situations stay distinguishable.
// One XCTest method per case so failures are reported per case.

import Foundation
import XCTest
@testable import Phext

final class RangeFixtureTests: XCTestCase {
    private var fixturesRoot: URL {
        // Tests/PhextTests/RangeFixtureTests.swift -> package root
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent() // PhextTests
            .appendingPathComponent("Fixtures/ranges")
    }

    private func field(_ fields: [String], _ key: String) -> String? {
        for f in fields {
            if let eq = f.firstIndex(of: "="), String(f[..<eq]) == key {
                return String(f[f.index(after: eq)...])
            }
        }
        return nil
    }

    private func runCase(_ name: String) throws {
        let caseDir = fixturesRoot.appendingPathComponent(name)
        let tsv = try String(contentsOf: caseDir.appendingPathComponent("expected.tsv"), encoding: .utf8)
        var expectedOps: Int? = nil
        var expectedBytes: Int? = nil
        var expectedSHA: String? = nil
        var opLines: [[String]] = []
        for line in tsv.components(separatedBy: "\n") {
            if line.isEmpty { continue }
            let fields = line.components(separatedBy: "\t")
            switch fields[0] {
            case "input_bytes": expectedBytes = Int(fields[1])
            case "input_sha256": expectedSHA = fields[1]
            case "ops": expectedOps = Int(fields[1])
            case "op": opLines.append(fields)
            default: break
            }
        }

        // input bytes + hash
        let inputData = try Data(contentsOf: caseDir.appendingPathComponent("input.phext"))
        let inputBytes = [UInt8](inputData)
        if let expectedBytes { XCTAssertEqual(inputBytes.count, expectedBytes, "\(name): input length") }
        if let expectedSHA { XCTAssertEqual(SHA256.hexDigest(inputBytes), expectedSHA, "\(name): input sha256") }
        let input = String(decoding: inputBytes, as: UTF8.self)
        XCTAssertEqual([UInt8](input.utf8), inputBytes, "\(name): input must be valid UTF-8 phext text")

        let chains = Phext.parseChains(input)
        XCTAssertFalse(chains.isEmpty, "\(name): at least one chain")
        let chain = chains[0]

        var opCount = 0
        for fields in opLines {
            opCount += 1
            let kind = fields[1]
            let input = fields[2]
            switch kind {
            case "parse_point":
                let parsed = Phext.parsePointAddress(input)
                if field(fields, "error") == "true" {
                    XCTAssertNil(parsed, "\(name): parse_point \(input) must fail")
                } else {
                    XCTAssertEqual(parsed?.description, field(fields, "canonical"),
                                   "\(name): parse_point \(input) canonical")
                }
            case "parse_range":
                let parsed = Phext.parseRangeAddress(input)
                if field(fields, "error") == "true" {
                    XCTAssertNil(parsed, "\(name): parse_range \(input) must fail")
                } else {
                    XCTAssertEqual(parsed?.description, field(fields, "canonical"),
                                   "\(name): parse_range \(input) canonical")
                }
            case "resolve_point":
                let parsed = Phext.parsePointAddress(input)
                XCTAssertNotNil(parsed, "\(name): resolve_point input must parse: \(input)")
                let resolved = parsed.flatMap { chain.resolvePoint($0) }
                if field(fields, "error") == "true" {
                    XCTAssertNil(resolved, "\(name): resolve_point \(input) must fail")
                } else {
                    let parts = (field(fields, "resolve") ?? "").components(separatedBy: "|")
                    XCTAssertEqual(parts.count, 3, "\(name): resolve_point \(input) expected tuple")
                    if parts.count == 3, let resolved {
                        XCTAssertEqual(resolved.0, UInt64(parts[0]), "\(name): resolve_point \(input) universe")
                        XCTAssertEqual(resolved.1.toString(), parts[1], "\(name): resolve_point \(input) coordinate")
                        XCTAssertEqual(resolved.2, Int(parts[2]), "\(name): resolve_point \(input) offset")
                    } else {
                        XCTFail("\(name): resolve_point \(input) must resolve")
                    }
                }
            case "fetch_point":
                let expectedData = try Data(contentsOf: caseDir.appendingPathComponent(field(fields, "file")!))
                let result = chain.fetchPoint(input)
                XCTAssertEqual([UInt8](result.utf8), [UInt8](expectedData),
                               "\(name): fetch_point \(input) bytes")
                let resolved = Phext.parsePointAddress(input).flatMap { chain.resolvePoint($0) } != nil
                XCTAssertEqual(resolved, field(fields, "resolved") == "true",
                               "\(name): fetch_point \(input) resolved flag")
            case "fetch_range":
                let expectedData = try Data(contentsOf: caseDir.appendingPathComponent(field(fields, "file")!))
                let result = chain.fetchRange(input)
                XCTAssertEqual([UInt8](result.utf8), [UInt8](expectedData),
                               "\(name): fetch_range \(input) bytes")
                let resolved = Phext.parseRangeAddress(input).flatMap { chain.resolveRange($0) } != nil
                XCTAssertEqual(resolved, field(fields, "resolved") == "true",
                               "\(name): fetch_range \(input) resolved flag")
            default:
                XCTFail("\(name): unknown op kind \(kind)")
            }
        }
        if let expectedOps {
            XCTAssertEqual(opCount, expectedOps, "\(name): op count")
        }
    }

    func testFixturePointBasics() throws { try runCase("point-basics") }
    func testFixtureOffsetForm() throws { try runCase("offset-form") }
    func testFixtureRangeWithinScroll() throws { try runCase("range-within-scroll") }
    func testFixtureRangeCrossScroll() throws { try runCase("range-cross-scroll") }
    func testFixtureRangeMultiverse() throws { try runCase("range-multiverse") }
    func testFixtureRangeUnicode() throws { try runCase("range-unicode") }

    func testFixtureInventory() throws {
        // cases.tsv lists exactly the six cases of the shared set
        let index = try String(contentsOf: fixturesRoot.appendingPathComponent("cases.tsv"), encoding: .utf8)
        let names = index.components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("case\t") }
            .map { $0.components(separatedBy: "\t")[0] }
        XCTAssertEqual(names, ["point-basics", "offset-form", "range-within-scroll",
                               "range-cross-scroll", "range-multiverse", "range-unicode"])
    }
}
