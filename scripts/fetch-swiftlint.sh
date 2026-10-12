#!/bin/bash
# Downloads a pinned SwiftLint portable binary into the build folder, so nothing is installed system-wide.
set -euo pipefail

version="$1"
expected_sha256="$2"
destination="$3"

archive="$(mktemp -d)/portable_swiftlint.zip"
curl --fail --silent --show-error --location \
  "https://github.com/realm/SwiftLint/releases/download/${version}/portable_swiftlint.zip" \
  --output "$archive"
actual_sha256="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "SwiftLint ${version} checksum mismatch: expected ${expected_sha256}, got ${actual_sha256}" >&2
  exit 1
fi
mkdir -p "$destination"
unzip -o -q "$archive" swiftlint -d "$destination"
chmod +x "$destination/swiftlint"
