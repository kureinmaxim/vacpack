#!/bin/bash
# Render the app icon from design/AppIcon.swift into the asset catalog, at every macOS size.
# Each size is drawn from the vector design, not scaled from one bitmap.
set -euo pipefail
cd "$(dirname "$0")/.."

out=App/Resources/Assets.xcassets/AppIcon.appiconset
renderer=.build/app-icon-renderer
mkdir -p .build "$out"
xcrun swiftc -O design/AppIcon.swift -o "$renderer"

images=()
for points in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((points * scale))
    suffix=$([ "$scale" = 2 ] && echo "@2x" || echo "")
    name="icon_${points}x${points}${suffix}.png"
    "$renderer" "$out/$name" "$pixels"
    images+=("    { \"idiom\" : \"mac\", \"size\" : \"${points}x${points}\", \"scale\" : \"${scale}x\", \"filename\" : \"$name\" }")
  done
done

{
  echo '{'
  echo '  "images" : ['
  for i in "${!images[@]}"; do
    [ "$i" -lt $((${#images[@]} - 1)) ] && echo "${images[$i]}," || echo "${images[$i]}"
  done
  echo '  ],'
  echo '  "info" : { "author" : "xcode", "version" : 1 }'
  echo '}'
} >"$out/Contents.json"
printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' >App/Resources/Assets.xcassets/Contents.json
echo "Rendered ${#images[@]} icon images into $out"
