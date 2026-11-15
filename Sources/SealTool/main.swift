// phext-seal-tool — tiny CLI over the Phext library's xz seal, used for
// cross-implementation verification (seal here, unseal with rs, and
// vice versa).
//
// Usage:
//   phext-seal-tool seal   <input-file> <output-file>
//   phext-seal-tool unseal <input-file> <output-file>

import Foundation
import Phext

let args = CommandLine.arguments
guard args.count == 4, args[1] == "seal" || args[1] == "unseal" else {
    FileHandle.standardError.write("usage: phext-seal-tool (seal|unseal) <input-file> <output-file>\n".data(using: .utf8)!)
    exit(2)
}

let input = try Data(contentsOf: URL(fileURLWithPath: args[2]))
let output: Data
if args[1] == "seal" {
    output = Data(try PhextSeal.sealBytes([UInt8](input)))
} else {
    output = Data(try PhextSeal.unseal([UInt8](input)))
}
try output.write(to: URL(fileURLWithPath: args[3]))
