# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Vacpack compresses images, videos and GIFs offline. Two independent codebases live here: a macOS app + CLI (Swift) and an experimental Windows app (C#/WPF, in `Windows/`). Project docs in `docs/` and `BUILD.md`, `VERSION_MANAGEMENT.md` and `Windows/README.md` are written in Russian.

## macOS commands

Needs macOS 14+, Xcode 26, and `brew install xcodegen ffmpeg pngquant gifski webp libavif ghostscript`.

```bash
scripts/bootstrap.sh          # check prerequisites, generate Xcode project and test inputs
scripts/check.sh              # swift-format lint --strict, version sync, package tests, app build + unit tests (--ui adds UI tests)
swift test --package-path Packages/CompressorKit                      # engine tests only
swift test --package-path Packages/CompressorKit --filter JobQueueTests   # single test class
swift run --package-path Packages/CompressorKit vacpack image photos/ --format webp
scripts/package.sh            # Release build -> .build/dist/Vacpack-<version>.dmg
scripts/install.sh            # install that DMG
```

`Vacpack.xcodeproj` is generated from `project.yml` by XcodeGen and is not committed — never edit it; run `xcodegen generate`. Code style is enforced by `.swift-format` (lint is `--strict` in `check.sh`).

## Windows commands

Run in PowerShell from the repo root (needs .NET 8 SDK and a Windows FFmpeg build with `ffmpeg.exe`/`ffprobe.exe`):

```powershell
.\scripts\windows.ps1 -Mode check -ToolsDirectory 'C:\ffmpeg\bin' [-RequireMediaTests]
.\scripts\windows.ps1 -Mode run -ToolsDirectory 'C:\ffmpeg\bin'
.\scripts\windows.ps1 -Mode package     # self-contained publish; -Mode installer builds the Inno Setup installer
```

`check` builds the app and two test projects (`Vacpack.Tests`, `Vacpack.Windows.Tests`), runs them as plain executables (custom `Program.cs` runners, not xUnit — no `dotnet test`), then launches the app with `--snapshot` to render a populated window and catch WPF binding errors. Media tests are skipped without FFmpeg unless `-RequireMediaTests`. The script sets `DOTNET_CLI_HOME` to `.build/dotnet-home`; `.build/` is the (git-ignored) build output and scratch area for both platforms.

## Architecture

- **macOS:** logic lives in the Swift package `Packages/CompressorKit` (engines, `JobQueue` actor, output naming/writing, tool location); `App/` is a thin SwiftUI shell (`CompressionModel` bridges the queue to the UI) and the `vacpack` CLI target in the same package drives every engine without UI. Encoders (ffmpeg, pngquant, gifski, cwebp, avifenc, gs) are **external processes run through `ProcessRunner`, never linked** — this keeps their GPL/AGPL licenses off the app. Don't introduce linking of these tools.
- **Windows:** `Windows/Vacpack.Core` is a separate reimplementation of the engines (spawns ffmpeg/ffprobe without a shell; `ToolLocator`, `EncodingCommand`, `CompressionEngine`, `MediaProbe`). `Windows/Vacpack.Windows` is the WPF UI. Quality tables (H.264/VP9 params, bitrate ceilings, WebP levels) are ported by hand from the Swift `*QualityTable.swift` files — keep them in sync when changing either side. Windows lacks HEIC/SVG/PDF/EPUB support.
- Shared output rules on both platforms: a result that is not smaller never replaces the original; names are `name-vacpack.ext` / `name-vacpack (1).ext`, existing files are never overwritten; macOS moves originals to Trash only after success, Windows never deletes originals.
- `docs/ARCHITECTURE.md` (decisions D1–D11, module layout), `docs/PLAN.md` (stages), `docs/QUALITY.md` (encoder params per quality level) explain intent; much of the layout in ARCHITECTURE.md describes planned modules not yet present.

## Versioning

The single source of truth is `project.yml` (`MARKETING_VERSION`, `VACPACK_RELEASE_DATE`). Windows reads it at build time via `Windows/Directory.Build.props`. Change versions only with `python3 scripts/update_version.py status|bump patch|minor|major|sync X.Y.Z` (supports `--dry-run`), which keeps README, CHANGELOG, Info.plist etc. in agreement; `check.sh` fails if they drift. Windows preview tags may carry a suffix (`v0.4.0-windows-preview.1`).
