#!/bin/bash
# Render the main window into PNGs through the Debug build's VACPACK_SNAPSHOT mode (no screen
# recording needed).
#   scripts/snapshot.sh [output dir]   design review with test fixtures: empty, with files and
#                                      after compressing, light and dark (default: .build/snapshots)
#   scripts/snapshot.sh --readme       README screenshots from scripts/make-demo.sh into docs/images
set -euo pipefail
cd "$(dirname "$0")/.."

readme=false
out=.build/snapshots
case "${1:-}" in
  --readme)
    readme=true
    out=docs/images
    ;;
  -h | --help)
    sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "") ;;
  *) out=$1 ;;
esac

mkdir -p "$out" .build
xcodegen generate --quiet
if ! xcodebuild -project Vacpack.xcodeproj -scheme Vacpack -destination 'platform=macOS' \
  -derivedDataPath .build/xcode build >.build/snapshot-build.log 2>&1; then
  grep -E 'error:' .build/snapshot-build.log | head -20 >&2
  echo "build failed; full log: .build/snapshot-build.log" >&2
  exit 1
fi
app=.build/xcode/Build/Products/Debug/Vacpack.app/Contents/MacOS/Vacpack

if $readme; then
  scripts/make-demo.sh >/dev/null
  source=.build/demo
  names=("Sunset over the ridge.jpg" "Morning fog.heic" "Desert dunes.png" "Fractal zoom.mp4" "Game of Life.gif")
else
  source=Packages/CompressorKit/Tests/Fixtures/generated
  [ -d "$source" ] || scripts/make-fixtures.sh
  names=(photo-1600x1200.jpg alpha-256.png photo.webp animation.gif video-640x360.mp4)
fi
# Work on copies: compressing writes results next to the inputs.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
files=()
for name in "${names[@]}"; do
  cp "$source/$name" "$work/"
  files+=("$work/$name")
done
list=$(
  IFS=:
  echo "${files[*]}"
)

# shot <png> <light|dark> [VAR=value...]
shot() {
  local png=$1 appearance=$2
  shift 2
  rm -f "$work"/*_compressed.*
  env VACPACK_SNAPSHOT="$png" VACPACK_SNAPSHOT_APPEARANCE="$appearance" "$@" "$app"
}

if $readme; then
  # A window just tall enough for the five demo files, as it would look on screen.
  shot "$out/drop-light.png" light VACPACK_SNAPSHOT_SIZE=900x690
  shot "$out/window-light.png" light VACPACK_SNAPSHOT_SIZE=900x690 VACPACK_UITEST_FILES="$list" \
    VACPACK_UITEST_COMPRESS=1
  shot "$out/window-dark.png" dark VACPACK_SNAPSHOT_SIZE=900x690 VACPACK_UITEST_FILES="$list" \
    VACPACK_UITEST_COMPRESS=1
  # The same tool Vacpack uses for PNG; exit 98/99 only means a file was already small enough.
  pngquant=/opt/homebrew/bin/pngquant
  [ -x "$pngquant" ] || pngquant=/usr/local/bin/pngquant
  "$pngquant" --quality=75-95 --speed 1 --strip --force --skip-if-larger --ext .png \
    "$out"/drop-light.png "$out"/window-light.png "$out"/window-dark.png || [ $? -ge 98 ]
else
  for appearance in light dark; do
    shot "$out/empty-$appearance.png" "$appearance"
    shot "$out/files-$appearance.png" "$appearance" VACPACK_UITEST_FILES="$list"
    shot "$out/results-$appearance.png" "$appearance" VACPACK_UITEST_FILES="$list" VACPACK_UITEST_COMPRESS=1
  done
fi
ls -l "$out"/*.png
