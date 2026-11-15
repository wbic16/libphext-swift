#!/usr/bin/env bash
# libphext-swift test step: the full XCTest suite, including the shared
# libphext 0.6 chain conformance fixtures (10 cases, 42 fetches).
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swift >/dev/null 2>&1; then
  echo "ERROR: 'swift' not found. Install a Swift toolchain first (https://www.swift.org/download/)." >&2
  exit 1
fi
swift test "$@"
