#!/bin/bash
# Generate small test inputs for the engines. Output is not committed (see .gitignore);
# rerun after a clean checkout. PDF and EPUB samples are added in stages 4 and 5.
set -euo pipefail
cd "$(dirname "$0")/.."

out=Packages/CompressorKit/Tests/Fixtures/generated
ffmpeg=/opt/homebrew/bin/ffmpeg
[ -x "$ffmpeg" ] || ffmpeg=/usr/local/bin/ffmpeg
[ -x "$ffmpeg" ] || { echo "ffmpeg not found; run scripts/bootstrap.sh" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$out"
ff() { "$ffmpeg" -hide_banner -loglevel error -y "$@"; }

# Video: 2 s test pattern with a sine tone, plus an odd-sized one without audio.
ff -f lavfi -i testsrc2=size=640x360:rate=30:duration=2 -f lavfi -i sine=frequency=440:duration=2 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$out/video-640x360.mp4"
ff -f lavfi -i testsrc2=size=321x241:rate=25:duration=1 -c:v libx264 -pix_fmt yuv420p \
  -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" "$out/video-no-audio.mp4"

# Images: photo-like JPEG, PNG with alpha, WebP, 300 DPI JPEG.
ff -f lavfi -i testsrc2=size=1600x1200 -frames:v 1 -q:v 2 "$out/photo-1600x1200.jpg"
ff -f lavfi -i "color=c=red@0.5:size=256x256,format=rgba" -frames:v 1 "$out/alpha-256.png"
/opt/homebrew/bin/cwebp -quiet -q 90 "$out/photo-1600x1200.jpg" -o "$out/photo.webp" 2>/dev/null \
  || ff -i "$out/photo-1600x1200.jpg" "$out/photo.webp"
cp "$out/photo-1600x1200.jpg" "$out/photo-300dpi.jpg"
sips -s dpiWidth 300 -s dpiHeight 300 "$out/photo-300dpi.jpg" >/dev/null

# Animated GIF.
ff -f lavfi -i testsrc2=size=320x240:rate=10:duration=2 "$out/animation.gif"

ls -lh "$out" | awk 'NR>1 {print $5, $9}'
