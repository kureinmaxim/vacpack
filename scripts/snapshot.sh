#!/bin/bash
# Render the main window into PNGs for design review: empty, with files, and after compressing,
# in light and dark. Uses the Debug build's VACPACK_SNAPSHOT mode, so no screen recording is needed.
#   scripts/snapshot.sh [output dir]   (default: .build/snapshots)
set -euo pipefail
cd "$(dirname "$0")/.."

out=${1:-.build/snapshots}
fixtures=Packages/CompressorKit/Tests/Fixtures/generated
[ -d "$fixtures" ] || scripts/make-fixtures.sh
mkdir -p "$out" .build
xcodegen generate --quiet
if ! xcodebuild -project Vacpack.xcodeproj -scheme Vacpack -destination 'platform=macOS' \
  -derivedDataPath .build/xcode build >.build/snapshot-build.log 2>&1; then
  grep -E 'error:' .build/snapshot-build.log | head -20 >&2
  echo "build failed; full log: .build/snapshot-build.log" >&2
  exit 1
fi
app=.build/xcode/Build/Products/Debug/Vacpack.app/Contents/MacOS/Vacpack

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
files=()
for name in photo-1600x1200.jpg alpha-256.png photo.webp animation.gif video-640x360.mp4; do
  cp "$fixtures/$name" "$work/"
  files+=("$work/$name")
done
list=$(IFS=:; echo "${files[*]}")

for appearance in light dark; do
  VACPACK_SNAPSHOT="$out/empty-$appearance.png" VACPACK_SNAPSHOT_APPEARANCE=$appearance "$app"
  VACPACK_UITEST_FILES=$list VACPACK_SNAPSHOT="$out/files-$appearance.png" \
    VACPACK_SNAPSHOT_APPEARANCE=$appearance "$app"
  rm -f "$work"/*_compressed.*
  VACPACK_UITEST_FILES=$list VACPACK_UITEST_COMPRESS=1 VACPACK_SNAPSHOT="$out/results-$appearance.png" \
    VACPACK_SNAPSHOT_APPEARANCE=$appearance "$app"
done
ls "$out"/*.png
