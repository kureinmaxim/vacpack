# Vacpack

Vacpack is a native macOS app and command-line tool that makes images, videos and GIFs smaller, entirely offline. Like vacuum packing: everything the file does not need is pumped out.

**Version:** `0.2.0`, released 18.10.2026 · [changelog](CHANGELOG.md) · [how versions are managed](VERSION_MANAGEMENT.md)

> **Status: early development.** Image, video and GIF compression work in the app and the CLI. PDF, EPUB, presets, the notch Drop Zone, folder monitoring and the rest are planned — see [the stage plan](docs/PLAN.md).

## What works today

- **Images** — JPEG, PNG, WebP, AVIF, HEIC/HEIF, TIFF, BMP and SVG in (DNG is supported but not yet tested); JPEG, PNG, WebP, AVIF or the same format out. Five quality levels, six resize modes (never upscaling), EXIF orientation applied, transparency kept (or flattened to white for JPEG). EXIF/IPTC/XMP, color profile, print resolution, file dates and Finder tags can be kept.
- **Videos** — MP4, MOV, WebM, MKV and other containers in; MP4, MOV, WebM or the same container out, or MP3 audio. H.264 or HEVC with x264/x265 (VideoToolbox optional on Apple Silicon), VP9 + Opus for WebM, output bitrate capped below the source's so already-compressed videos still shrink, transparency kept in WebM and MOV, every audio track kept, resolution presets and frame-rate caps that only ever go down. Falls back to software encoding when the media engine is busy.
- **GIFs** — compress animated GIFs or turn videos into GIFs with gifski: quality, size and frame rate (10–50 fps), transparency and frame timing preserved.
- **Safe by default** — a result that is not smaller never replaces the original, originals go to the Trash only after success, and nothing ever leaves your Mac.

## Requirements

- macOS 14 or later, Xcode 26 (after installing or updating Xcode, run `sudo xcodebuild -runFirstLaunch` once)
- Tools from Homebrew:

```bash
brew install xcodegen ffmpeg pngquant gifski webp libavif ghostscript
```

Vacpack runs these tools as separate programs and never links them, so their licenses apply to them alone.

## Build and test

```bash
scripts/bootstrap.sh   # check prerequisites, generate the Xcode project and test inputs
scripts/check.sh       # swift-format lint, engine tests, app build and tests (--ui adds UI tests)
open Vacpack.xcodeproj
```

`Vacpack.xcodeproj` is generated from `project.yml` with XcodeGen and is not committed.

The step-by-step build guide, from a fresh clone to the DMG, with common problems: [BUILD.md](BUILD.md) (in Russian).

The app icon is drawn in code (`design/AppIcon.swift`); `scripts/make-icon.sh` renders every macOS size into the asset catalog.

## Install on your Mac

```bash
scripts/package.sh          # build Release and pack .build/dist/Vacpack-<version>.dmg
scripts/package.sh --open   # the same, then open the DMG in Finder
```

Drag **Vacpack** into **Applications** from the opened DMG. The app is a universal build (Apple Silicon and Intel). Each run stamps a new build number (UTC date and time), so a reinstalled app never shows the Dock icon of an earlier build.

The build is ad-hoc signed, not notarized: it opens without warnings on the Mac that built it, while on other Macs macOS blocks it until you choose **System Settings → Privacy & Security → Open Anyway**. Those Macs also need the Homebrew tools listed above.

## Command line

The engines are a Swift package (`Packages/CompressorKit`) with a `vacpack` command:

```bash
swift run --package-path Packages/CompressorKit vacpack tools
swift run --package-path Packages/CompressorKit vacpack image photos/ --format webp --max-long-edge 2000
swift run --package-path Packages/CompressorKit vacpack video clip.mov --format mp4 --resolution 1080p
swift run --package-path Packages/CompressorKit vacpack video clip.mov --format gif --gif-fps 15 --gif-max-width 480
swift run --package-path Packages/CompressorKit vacpack gif animation.gif --quality good --percent 50
```

`image`, `video` and `gif` describe their options with `--help`; every command can print results as `--json`.

## Project documents (in Russian)

- [docs/SPEC.md](docs/SPEC.md) — the feature specification, compiled from public documentation of an existing macOS compressor
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design decisions and module layout
- [docs/PLAN.md](docs/PLAN.md) — stages with acceptance criteria
- [docs/QUALITY.md](docs/QUALITY.md) — encoder parameters per quality level and measurements
- [BUILD.md](BUILD.md) — how to build, test and package
- [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md) — how versions are changed and kept in sync

Vacpack is an independent implementation written from scratch; it contains no code from other compression apps and is not affiliated with them.

## License

Vacpack is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License version 3](LICENSE).

The compression tools it runs (FFmpeg, pngquant, gifski, libwebp, libavif, Ghostscript) are installed separately and keep their own licenses.
