#!/usr/bin/env bash
# libphext-swift publish step. There is no package registry for this
# port: distribution is a git tag on the exo branch, in the family
# pattern. The script tests, then (only when PUBLISH_CONFIRM=1) tags
# v<VERSION> at the current HEAD and pushes the tag.
#
# The version is read from Sources/Phext/Phext.swift (Phext.version)
# and README.md, and the publish FAILS if they disagree.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(grep -oPm1 '(?<=public static let version = ")[^"]+' Sources/Phext/Phext.swift)"
README_VERSION="$(grep -oPm1 'libphext-rs.*at \*\*\K[0-9]+\.[0-9]+\.[0-9]+' README.md || true)"
if [ -n "$README_VERSION" ] && [ "$README_VERSION" != "$VERSION" ]; then
  echo "ERROR: version mismatch — Sources/Phext/Phext.swift says '$VERSION' but README.md says '$README_VERSION'." >&2
  exit 1
fi
echo "== libphext-swift publish: version ${VERSION} =="
echo "-- step 1/2: tests"
"$(dirname "$0")/test.sh"
echo "-- step 2/2: tag"
echo "Will tag: v${VERSION} at $(git rev-parse --short HEAD) on $(git branch --show-current)"
if [ "${PUBLISH_CONFIRM:-}" != "1" ]; then
  echo "STOP: dry run only. Re-run with PUBLISH_CONFIRM=1 to create and push the tag."
  exit 0
fi
git tag "v${VERSION}"
git push origin "v${VERSION}"
echo "Published libphext-swift ${VERSION} (tag v${VERSION})."
