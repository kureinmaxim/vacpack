#!/bin/bash
# Build the Release app and pack it into a drag-to-install DMG.
#   scripts/package.sh          → .build/dist/Vacpack-<version>.dmg
#   scripts/package.sh --open   also open the DMG in Finder
#
# The app is ad-hoc signed: it runs on this Mac, but on other Macs Gatekeeper asks for
# "Open Anyway" until Developer ID signing and notarization arrive (PLAN stage 13).
set -euo pipefail
cd "$(dirname "$0")/.."

open_dmg=false
case "${1:-}" in
  "") ;;
  --open) open_dmg=true ;;
  -h | --help)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $1 (use --open or --help)" >&2
    exit 2
    ;;
esac

step() { printf '\n==> %s\n' "$1"; }
fail() {
  echo "package failed: $1" >&2
  exit 1
}

mkdir -p .build
step "Generate Xcode project"
xcodegen generate --quiet

step "Build Release"
if ! xcodebuild -project Vacpack.xcodeproj -scheme Vacpack -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .build/release build >.build/release-build.log 2>&1; then
  grep -E 'error:' .build/release-build.log | head -20 >&2
  fail "xcodebuild failed; full log: .build/release-build.log"
fi
app=.build/release/Build/Products/Release/Vacpack.app
[ -d "$app" ] || fail "$app was not produced"
codesign --verify --deep --strict "$app" || fail "the app's signature does not verify"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")

step "Pack DMG"
dist=.build/dist
dmg="$dist/Vacpack-$version.dmg"
stage="$dist/stage"
rm -rf "$stage" "$dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Vacpack.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Vacpack $version" -srcfolder "$stage" -ov -format UDZO "$dmg"
rm -rf "$stage"
hdiutil verify -quiet "$dmg" || fail "the DMG checksum does not verify"

printf '\nCreated %s (%s, version %s, %s)\n' "$dmg" "$(du -h "$dmg" | cut -f1 | tr -d ' ')" "$version" \
  "$(lipo -archs "$app/Contents/MacOS/Vacpack")"
echo "Ad-hoc signed: runs on this Mac; other Macs need System Settings → Privacy & Security → Open Anyway."
$open_dmg && open "$dmg"
exit 0
