#!/bin/bash
# Build the Release app and pack it into a drag-to-install DMG.
#   scripts/package.sh          → .build/dist/Vacpack-<version>.dmg
#   scripts/package.sh --open   also open the DMG in Finder
#
# Every run stamps a new build number (CFBundleVersion, UTC date.time such as 20261018.143205),
# so macOS does not keep the Dock icon or other cached details of an earlier build, and the commit
# with its push date, which About Vacpack shows.
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
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
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
python3 scripts/update_version.py status >/dev/null ||
  fail "version files are out of sync; see python3 scripts/update_version.py status"

step "Generate Xcode project"
xcodegen generate --quiet

step "Build Release"
# Two integers that only grow: macOS compares CFBundleVersion component by component.
build=$(date -u +%Y%m%d.%H%M%S)
# The commit the build comes from and when it reached GitHub, for the About panel. The push time is
# the local reflog entry of origin/main; a build made before pushing says so.
source_rev="" source_date=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  stamp='%d.%m.%Y %H:%M'
  source_rev=$(git rev-parse --short HEAD)
  if [ -n "$(git status --porcelain)" ]; then
    source_rev+=" with local changes"
    source_date="not committed yet"
  elif [ "$(git rev-parse HEAD)" = "$(git rev-parse -q --verify refs/remotes/origin/main || true)" ] &&
    git log -g -1 --format=%gs refs/remotes/origin/main | grep -q push; then
    source_date="pushed $(git log -g -1 --format=%gd --date=format-local:"$stamp" refs/remotes/origin/main |
      sed -E 's/.*@\{(.*)\}$/\1/')"
  else
    source_date="committed $(git log -1 --format=%cd --date=format-local:"$stamp"), not pushed yet"
  fi
fi
if ! xcodebuild -project Vacpack.xcodeproj -scheme Vacpack -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .build/release CURRENT_PROJECT_VERSION="$build" VACPACK_SOURCE="$source_rev" \
  VACPACK_SOURCE_DATE="$source_date" build >.build/release-build.log 2>&1; then
  grep -E 'error:' .build/release-build.log | head -20 >&2
  fail "xcodebuild failed; full log: .build/release-build.log"
fi
app=.build/release/Build/Products/Release/Vacpack.app
[ -d "$app" ] || fail "$app was not produced"
codesign --verify --deep --strict "$app" || fail "the app's signature does not verify"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")" = "$build" ] ||
  fail "the app's CFBundleVersion is not the stamped build $build"
[ "$(/usr/libexec/PlistBuddy -c 'Print VacpackSource' "$app/Contents/Info.plist")" = "$source_rev" ] ||
  fail "the app does not carry its source commit $source_rev"

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

printf '\nCreated %s (%s, version %s, build %s, %s)\n' "$dmg" "$(du -h "$dmg" | cut -f1 | tr -d ' ')" "$version" \
  "$build" "$(lipo -archs "$app/Contents/MacOS/Vacpack")"
[ -z "$source_rev" ] || echo "Source: commit $source_rev, $source_date"
echo "Ad-hoc signed: runs on this Mac; other Macs need System Settings → Privacy & Security → Open Anyway."
$open_dmg && open "$dmg"
exit 0
