#!/bin/bash
# Builds a universal (Apple silicon + Intel) Terminator.app into build/.
#
#   ./scripts/build-app.sh
#
# The app is ad-hoc signed by default. For a public release, pass a Developer ID identity:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

MIN_MACOS="12.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# Build and sign in a temporary folder. If the project lives in iCloud Drive (e.g. ~/Documents), iCloud keeps
# adding Finder metadata to the bundle, and codesign refuses to sign a bundle that has any.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Terminator.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling for arm64 and x86_64 (macOS $MIN_MACOS or later)..."
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" main.swift -o "$WORK/Terminator-$arch"
done
lipo -create "$WORK/Terminator-arm64" "$WORK/Terminator-x86_64" -output "$APP/Contents/MacOS/Terminator"

cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"

echo "Signing..."
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --deep --strict "$APP"

rm -rf build/Terminator.app
mkdir -p build
ditto --noextattr --noqtn "$APP" build/Terminator.app

echo "Built build/Terminator.app"
