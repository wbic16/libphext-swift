// Seal.swift — the xz seal, ported 1:1 from libphext-rs 0.6.0
// (src/seal.rs). Swift has no stdlib lzma, so encoding/decoding go
// through the CLzma shim target over the system liblzma: preset 6 +
// CRC64, exactly the rs (xz2) encoder configuration — sealed bytes are
// byte-identical to rs's for the same input.

import CLzma
import Foundation

public enum PhextSealError: Error {
    case encodeFailed(Int32)
    case decodeFailed(Int32)
    case invalidUTF8
}

public enum PhextSeal {
    public static let sealPreset: UInt32 = 6

    public static func seal(_ input: String) throws -> [UInt8] {
        try sealBytes([UInt8](input.utf8))
    }

    public static func sealBytes(_ input: [UInt8]) throws -> [UInt8] {
        var out: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0
        let rc: Int32
        if input.isEmpty {
            var dummy: UInt8 = 0
            rc = phext_xz_encode(&dummy, 0, sealPreset, &out, &outLen)
        } else {
            rc = input.withUnsafeBufferPointer { ptr in
                phext_xz_encode(ptr.baseAddress, input.count, sealPreset, &out, &outLen)
            }
        }
        guard rc == 0, let buffer = out else {
            throw PhextSealError.encodeFailed(rc)
        }
        defer { phext_xz_free(buffer) }
        return [UInt8](UnsafeBufferPointer(start: buffer, count: outLen))
    }

    public static func unseal(_ data: [UInt8]) throws -> [UInt8] {
        var out: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0
        let rc: Int32
        if data.isEmpty {
            var dummy: UInt8 = 0
            rc = phext_xz_decode(&dummy, 0, &out, &outLen)
        } else {
            rc = data.withUnsafeBufferPointer { ptr in
                phext_xz_decode(ptr.baseAddress, data.count, &out, &outLen)
            }
        }
        guard rc == 0, let buffer = out else {
            throw PhextSealError.decodeFailed(rc)
        }
        defer { phext_xz_free(buffer) }
        return [UInt8](UnsafeBufferPointer(start: buffer, count: outLen))
    }

    public static func unsealString(_ data: [UInt8]) throws -> String {
        let bytes = try unseal(data)
        guard let text = String(validating: bytes, as: UTF8.self) else {
            throw PhextSealError.invalidUTF8
        }
        return text
    }
}
