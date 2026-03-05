#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./scripts/release.sh <version> (e.g. 1.0.0)}"

git tag "v$VERSION"
git push origin "v$VERSION"

echo "Tag v$VERSION pushed — GitHub Action will build the DMG and create the release."
