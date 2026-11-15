# libphext-swift

The Swift port of phext, tracking the reference implementation
[libphext-rs](https://github.com/wbic16/libphext-rs) at **0.6.1**.

Phext is composable, relational text: plain text (scrolls) addressed in an
11-dimensional space — a 9-dimension coordinate
(`Library.Shelf.Series/Collection.Volume.Book/Chapter.Section.Scroll`)
where each scroll is itself 2D text. This port mirrors the Rust reference
byte-for-byte:

- **Core** (`Phext`): `Coordinate` (unbounded `UInt64` components),
  `fetch` / `insert` / `replace` / `remove` / `rangeReplace`,
  `phokenize` / `dephokenize`, `explode` / `implode`, `merge`, `subtract`,
  `expand` / `contract`, `normalize`, `index` / `offset`, summaries and
  maps, the XXH3-128 `checksum` / `manifest`, and `soundexV1`.
  Address parsing comes in both rs forms: the lenient `toCoordinate`
  and the strict `Coordinate.parse` (throws `PhextParseError`).
- **Binary scrolls** (`PhextBinary`): the canonical
  `phext-binary:1:base64` scroll format — `encodeScroll` / `decodeScroll`,
  `insertBinary` / `replaceBinary` / `fetchBinary`, and the byte-oriented
  `insertBytes` / `replaceBytes` / `ingest` / `phokenizeBytes`, which apply
  the base64-verbatim ingestion rule (valid UTF-8 stays text; anything
  else is stored as a binary scroll holding the base64 of the exact
  observed bytes).
- **The xz seal** (`PhextSeal`): a finished phext sealed with xz at
  preset 6 + CRC64, byte-identical to the Rust seal for the same input
  (verified cross-implementation both directions). Swift has no stdlib
  lzma, so the seal goes through a small C shim target (`CLzma`) over the
  system liblzma.
- **Chains** (`Chain`, `Phext.parseChains` / `serializeChains`): whole
  phexts joined by chain break `0x02` and terminated by chain close
  `0x03`, with `$N:` multiverse addressing (`Chain.fetch`) — a bare
  address means universe 1, and misses return `""`.
- **Addressing** (`ScrollPosition`, `PointAddress`, `RangeAddress`,
  `Phext.parsePointAddress` / `parseRangeAddress`): the v0.6.1 point,
  offset, and range forms — `$N:<coordinate>@<line>,<column>[+<offset>]`
  points and `<point>-<point>` ranges spanning scrolls and universes.
  Positions are 1-based caret boundaries (half-open), columns and
  offsets count Unicode scalar values, and range endpoints normalize to
  ascending order (direction is discarded; `$1:` is never emitted).
  `Chain.resolvePoint` / `resolveRange` return `nil` on any
  out-of-range endpoint — never a clamp — and `Chain.fetchPoint` /
  `fetchRange` return `""` on any failure; a range fetch is a phext
  (chain) fragment with no trailing chain close.

## Requirements

- Swift 5.9+ (developed and tested with Swift 6.0.3 on Ubuntu 24.04).
- For the xz seal: the system liblzma (`liblzma-dev` on Debian/Ubuntu).
- For `checksum` / `manifest`: libxxhash at runtime (`libxxhash0` is
  enough — it is resolved dynamically; without it those two functions
  return `nil` and everything else works).

## Build and test

```sh
scripts/build.sh   # swift build -c release
scripts/test.sh    # swift test (unit suites + the shared chain and range fixtures)
```

The test suite ports the Rust suites (`phext`, `phokenize`, `binary`,
`seal`, `chain`, `address`) as XCTest and runs the shared conformance
fixtures: the chain fixtures in `Tests/PhextTests/Fixtures/chains/`
(10 cases, 42 fetches, each checked for structure, per-scroll hashes,
byte-identical round-trip, and byte-exact fetches) and the v0.6.1 range
fixtures in `Tests/PhextTests/Fixtures/ranges/` (6 cases, 69 ops,
consumed op-by-op from `expected.tsv`).

## Usage

```swift
import Phext

var doc = Phext.insert("", Phext.toCoordinate("1.1.1/1.1.1/1.1.1"), "Hello")
doc = Phext.insert(doc, Phext.toCoordinate("1.1.1/1.1.1/1.1.2"), "World")
let scroll = Phext.fetch(doc, Phext.toCoordinate("1.1.1/1.1.1/1.1.2")) // "World"

let sealed = try PhextSeal.seal(doc)          // xz, preset 6 + CRC64
let restored = try PhextSeal.unsealString(sealed)

let chains = Phext.parseChains("edition one\u{02}edition two\u{03}")
let fromUniverse2 = chains[0].fetch("$2:1.1.1/1.1.1/1.1.1")
```

`phext-seal-tool` is a small executable product used for
cross-implementation seal verification:

```sh
swift run phext-seal-tool seal input.phext sealed.xz
swift run phext-seal-tool unseal sealed.xz output.phext
```

## Publishing

There is no package registry for this port; distribution is a git tag.
`scripts/publish.sh` runs the tests, then — only with
`PUBLISH_CONFIRM=1` — tags `v<version>` on the current `exo` tip and
pushes the tag.

## License

MIT — see `LICENSE`. Copyright (c) 2024–2025 Will Bickford (Phext, Inc.).
