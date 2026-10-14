#!/bin/bash
# Builds the drag-to-Applications installer: build/Terminator-<version>.dmg
#
#   ./scripts/build-dmg.sh
#
# The installer window is laid out through Finder (AppleScript), so the first run may ask whether your
# terminal can control Finder - allow it. A Finder window will flash up on screen while it works.
# For a public release, sign with a Developer ID identity:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VOLNAME="Terminator"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DMG="build/$VOLNAME-$VERSION.dmg"
MOUNT="/Volumes/$VOLNAME"

# Window geometry in points. The icons are placed to line up with the arrow in the background art
# (keep these in step with scripts/make-dmg-background.swift).
WIN_X=200; WIN_Y=120; WIN_W=660; WIN_H=400; TITLEBAR=28
APP_X=165; LINK_X=495; ICONS_Y=190; ICON_SIZE=128

if [ -e "$MOUNT" ]; then
    echo "error: $MOUNT is already mounted - eject it first." >&2
    exit 1
fi

./scripts/build-app.sh

# Work in a temporary folder (see build-app.sh); never leave a disk mounted if something fails.
WORK="$(mktemp -d)"
cleanup() {
    for volume in "$MOUNT" "$WORK/verify"; do
        if [ -d "$volume" ]; then hdiutil detach "$volume" -force >/dev/null 2>&1 || true; fi
    done
    rm -rf "$WORK"
}
trap cleanup EXIT
STAGE="$WORK/stage"
RW="$WORK/rw.dmg"

# Succeeds when the .DS_Store at $1 holds the window size, icon size and background picture we asked for.
layout_saved() {
    python3 -I - "$1" "$ICON_SIZE" "$WIN_W" "$((WIN_H + TITLEBAR))" <<'PY'
import plistlib, struct, sys
path, icon, w, h = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
try:
    data = open(path, "rb").read()
except OSError:
    sys.exit(1)
def record(code):
    i = data.find(code + b"blob")
    if i < 0:
        return {}
    n = struct.unpack(">I", data[i + 8:i + 12])[0]
    try:
        return plistlib.loads(data[i + 12:i + 12 + n])
    except Exception:
        return {}
window, view = record(b"bwsp"), record(b"icvp")
saved = (view.get("iconSize") == icon and view.get("backgroundType") == 2
         and window.get("WindowBounds", "").endswith("{%s, %s}}" % (w, h)))
sys.exit(0 if saved else 1)
PY
}

echo "Drawing the installer background..."
swiftc -O scripts/make-dmg-background.swift -o "$WORK/make-dmg-background"
"$WORK/make-dmg-background" "$WORK" >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff"

echo "Staging..."
mkdir -p "$STAGE/.background"
ditto --noextattr --noqtn build/Terminator.app "$STAGE/Terminator.app"
xattr -cr "$STAGE/Terminator.app"   # drop Finder metadata iCloud may have added to the copy in build/
codesign --verify --deep --strict "$STAGE/Terminator.app"   # the copy that ships must still be validly signed
ln -s /Applications "$STAGE/Applications"
cp "$WORK/background.tiff" "$STAGE/.background/background.tiff"

echo "Creating the disk image..."
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -size 24m "$RW" >/dev/null
hdiutil attach "$RW" -noautoopen -noverify >/dev/null
cp AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"   # give the mounted disk the app's icon

echo "Laying out the window in Finder..."
osascript <<APPLESCRIPT
with timeout of 90 seconds
    tell application "Finder"
        tell disk "$VOLNAME"
            open
            delay 1
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H + TITLEBAR))}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to $ICON_SIZE
            set background picture of viewOptions to file ".background:background.tiff"
            set position of item "Terminator.app" of container window to {$APP_X, $ICONS_Y}
            set position of item "Applications" of container window to {$LINK_X, $ICONS_Y}
            delay 1
        end tell
    end tell
end timeout
APPLESCRIPT
sleep 6

# Finder saves the layout to .DS_Store when the window closes - and then, a few seconds later, overwrites it
# with default settings. So catch the good copy the moment it appears, let Finder finish, and put that copy
# back before ejecting.
osascript -e "tell application \"Finder\" to tell disk \"$VOLNAME\" to close"
GOOD="$WORK/layout.DS_Store"
for _ in $(seq 1 80); do
    if layout_saved "$MOUNT/.DS_Store"; then
        cp "$MOUNT/.DS_Store" "$GOOD"
        break
    fi
    sleep 0.25
done
if [ ! -f "$GOOD" ]; then
    echo "error: Finder did not save the window layout." >&2
    exit 1
fi
sleep 10
cp "$GOOD" "$MOUNT/.DS_Store"
rm -rf "$MOUNT/.fseventsd"
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync

for attempt in 1 2 3 4 5; do
    hdiutil detach "$MOUNT" >/dev/null 2>&1 && break
    sleep 2
done

echo "Compressing..."
mkdir -p build
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

if [ "${SIGN_IDENTITY:--}" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

echo "Checking the finished image..."
mkdir -p "$WORK/verify"
hdiutil attach "$DMG" -readonly -nobrowse -noautoopen -mountpoint "$WORK/verify" >/dev/null
layout_saved "$WORK/verify/.DS_Store" || { echo "error: the window layout did not make it into the image." >&2; exit 1; }
codesign --verify --deep --strict "$WORK/verify/Terminator.app"
hdiutil detach "$WORK/verify" >/dev/null

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
