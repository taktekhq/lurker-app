#!/usr/bin/env bash
# Generates the Xcode project, runs LurkerKit's tests, then verifies the app
# and share extension compile for a real device (no simulator, no signing).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found on PATH (expected at ~/.local/bin/xcodegen). See README.md." >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> swift test --package-path LurkerKit"
swift test --package-path LurkerKit

echo "==> xcodebuild -scheme Lurker -destination generic/platform=iOS (no simulator, no signing)"
xcodebuild \
  -project Lurker.xcodeproj \
  -scheme Lurker \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> build.sh: all green"
