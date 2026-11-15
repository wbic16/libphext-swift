// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "libphext-swift",
    products: [
        .library(name: "Phext", targets: ["Phext"]),
        .executable(name: "phext-seal-tool", targets: ["SealTool"]),
    ],
    targets: [
        // C shim over the system liblzma (xz seal) and, when its headers are
        // available at build time on the host, libxxhash (XXH3-128 checksum).
        // The shim itself only requires liblzma; the xxhash entry point is
        // resolved dynamically — see shim.c.
        .target(
            name: "CLzma",
            linkerSettings: [.linkedLibrary("lzma")]
        ),
        .target(name: "Phext", dependencies: ["CLzma"]),
        .executableTarget(name: "SealTool", dependencies: ["Phext"]),
        .testTarget(name: "PhextTests", dependencies: ["Phext"]),
    ]
)
