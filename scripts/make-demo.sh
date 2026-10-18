#!/bin/bash
# Make demo files for README screenshots in .build/demo: three photos drawn by design/DemoImages.swift,
# a fractal-zoom video and a Game of Life GIF from ffmpeg's generators, recolored into the app's palette. All of it is generated, so
# the screenshots can be published with the project.
set -euo pipefail
cd "$(dirname "$0")/.."

out=.build/demo
ffmpeg=/opt/homebrew/bin/ffmpeg
[ -x "$ffmpeg" ] || ffmpeg=/usr/local/bin/ffmpeg
[ -x "$ffmpeg" ] || { echo "ffmpeg not found; run scripts/bootstrap.sh" >&2; exit 1; }
ff() { "$ffmpeg" -hide_banner -loglevel error -y "$@"; }

rm -rf "$out"
mkdir -p "$out" .build
xcrun swiftc -O design/DemoImages.swift -o .build/demo-images-renderer
.build/demo-images-renderer "$out"

# Durations go on the generator inputs: they never end on their own.
ff -f lavfi -t 3 -i "mandelbrot=size=960x540:rate=25" -f lavfi -t 3 -i "sine=frequency=220" \
  -vf "format=gray,format=rgb24,curves=r='0/0.17 0.5/0.71 1/0.91':g='0/0.37 0.5/0.33 1/0.72':b='0/0.54 0.5/0.17 1/0.29'" \
  -c:v libx264 -crf 14 -pix_fmt yuv420p -c:a aac -b:a 192k "$out/Fractal zoom.mp4"
echo "Wrote Fractal zoom.mp4"

ff -f lavfi -t 3 -i "life=size=320x200:rate=12:mold=10:ratio=0.12:life_color=#E8B84A:death_color=#2C5F8A:mold_color=#B5532B" \
  -vf "scale=640:400:flags=neighbor,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse" \
  "$out/Game of Life.gif"
echo "Wrote Game of Life.gif"
