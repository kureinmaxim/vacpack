# Changelog

Notable changes to Vacpack. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/), MAJOR.MINOR.PATCH. How to release a version: [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md).

## [Unreleased]

## [0.2.0] - 2026-10-18

### Added

- About Vacpack links to the project and its author on GitHub and shows the commit the build came from and when it was pushed.
- Help menu: Vacpack on GitHub, Release Notes, Report an Issue, Author on GitHub.

### Changed

- File kinds use a vintage print palette — mustard for images, rust for videos, jade for GIF — instead of pink and violet; "Original kept" is neutral gray.

## [0.1.1] - 2026-10-18

### Changed

- A colorful window in the icon's colors: a drop screen with the app icon and file kinds, file cards with Quick Look thumbnails, savings badges and colored states, kind badges on the settings rows, overall progress and a total of what was saved. Main buttons and the app's accent color use the icon's gradient, in light and dark mode.

### Added

- Drag a finished file out of the window into Mail, Messages or Finder; right-click a file to show or open the result or the original.
- `scripts/snapshot.sh` renders the window in light and dark for design review (Debug build, no screen recording needed).

## [0.1.0] - 2026-10-18

The first version: image, video and GIF compression in the app and the `vacpack` command-line tool.

### Added

- Images: JPEG, PNG, WebP, AVIF, HEIC/HEIF, TIFF, BMP and SVG in; JPEG, PNG, WebP, AVIF or the same format out. Five quality levels, six resize modes that never upscale, and metadata, color profile, file dates and Finder tags that can be kept.
- Videos: MP4, MOV, WebM, MKV and other containers in; MP4, MOV, WebM or the same container out, or MP3 audio. x264/x265 by default with the output bitrate capped below the source's, so already-compressed videos still shrink; VideoToolbox is optional.
- GIFs: compress animated GIFs or turn videos into GIFs with gifski.
- A result that is not smaller never replaces the original.
- `scripts/package.sh` builds the Release app and a drag-to-install DMG; each build gets a new build number.
- The app icon, drawn in code.
- One source for the version: `scripts/update_version.py`, `vacpack --version`, and the version with its release date in About Vacpack.
