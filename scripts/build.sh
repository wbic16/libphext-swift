#!/usr/bin/env bash
# libphext-swift build step (Release). Prerequisites: a Swift toolchain
# on PATH (swift.org tarball or system package) and liblzma (the xz seal
# links the system library: liblzma-dev on Debian/Ubuntu).
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swift >/dev/null 2>&1; then
  echo "ERROR: 'swift' not found. Install a Swift toolchain first (https://www.swift.org/download/)." >&2
  exit 1
fi
swift build -c release
echo "Built libphext-swift (release)."
