# Changelog

Notable changes to Vacpack. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/), MAJOR.MINOR.PATCH. How to release a version: [VERSION_MANAGEMENT.md](VERSION_MANAGEMENT.md).

## [Unreleased]

## [0.6.2] - 2026-10-23

### Fixed

- Windows: the folder icons (next to the list rows and the output folder) are no longer clipped at the edge.

## [0.6.1] - 2026-10-23

## [0.6.0] - 2026-10-23

### Added

- Windows: the window opens much smaller and narrower (about 700 × 560 device-independent units on a typical monitor; the size follows the work area) and grows by itself when the first files are added, giving the space back when the queue is emptied. The settings panel scrolls with a thin scroll bar when a long block such as Strong compression is open, instead of shrinking the text; the list columns are narrower.
- Windows: **strong compression** (experimental), Advanced ▸ Strong compression, for video. Modern video codecs: AV1 (SVT-AV1), HEVC (x265) and H.266 / VVC (vvenc, very slow). “Fit into N MB” picks the bitrate from the duration and retries up to four times until the file fits. Presets Strong / Maximum / Extreme (long side 640–320 px, 15–6 frames/s, mono Opus sound at 32–8 kbps), plus black and white, noise smoothing and dropping repeated frames. The size list now goes down to 320 px and the frame-rate list to 6. How it works: [docs/STRONG_COMPRESSION.md](docs/STRONG_COMPRESSION.md); macOS is a task there.

## [0.5.3] - 2026-10-23

### Changed

- Windows: a more compact window. The header, margins, buttons, list rows and the drop area are smaller, the settings panel is narrower and has no scroll bar: if it does not fit, its content shrinks instead. The first window size follows the monitor's work area (about 56% by 68%, within 860–1240 by 580–840 device-independent units), and the minimum size is 820 × 580.

## [0.5.2] - 2026-10-22

### Changed

- macOS: “Keep transparency” and “Hardware encoding” show a tip on hover. “Remove audio” stays without one.
- macOS: a file that did not shrink is marked “Not smaller” instead of “Original kept”. The row says there is no new file.

## [0.5.1] - 2026-10-21

## [0.5.0] - 2026-10-21

### Added

- macOS: interface language, English (the default) or Russian, chosen in the app menu under Language and applied after a restart. Strings live in `App/Resources/Localizable.xcstrings`.
- Windows: interface language, English (the default) or Russian, chosen in the window header and applied after a restart. The choice is kept in `%LOCALAPPDATA%\Vacpack\settings.json`.

## [0.4.1] - 2026-10-21

### Added

- Windows: the developer and a link to the project on GitHub in the window header, as in the macOS About panel.

## [0.4.0] - 2026-10-19

### Added

- Experimental Windows application (WPF / .NET 8) with local FFmpeg image, video, GIF and audio processing, drag-and-drop, a cancellable queue, safe output naming and generated-media checks. Build and limitations: [Windows/README.md](Windows/README.md).
- Photo, video and GIF thumbnails on Windows: background loading, EXIF orientation, short-video fallback, bounded memory cache and cancellation when rows are removed.
- Self-contained Windows x64 installer and portable ZIP, a source-commit manifest and SHA-256 checksums. Release packaging requires committed sources and a clean working tree.

### Changed

- Refined the Windows interface with compact controls, settings that follow the queued media types, clearer file results, per-file actions, a fixed output-folder selector and direct recompression with changed settings.

## [0.3.1] - 2026-10-18

### Fixed

- Sound from a long video stopped after a split second in MP3 and M4A (a 67-minute video gave 0.02 s and 16 KB): taking the cover frame in the same ffmpeg run closed the file as soon as that frame was written. The cover is now made in its own step, and a sound file shorter than 90% of the source is reported as an error instead of a success.

## [0.3.0] - 2026-10-18

### Added

- Sound from video as M4A, MP3 or Opus. A Speech (podcast) profile makes it mono with even loudness (−16 LUFS) at a low bitrate — about 29 MB an hour in M4A or MP3, 14 MB in Opus — for listening as a podcast or sending through Telegram, Delta Chat and other messengers. M4A and MP3 get a frame from the video as cover art and the file name as the title. CLI: `--format m4a|mp3|opus --audio music|speech`.
- A Share button on finished files (Telegram, Messages, Mail, AirDrop and other share extensions); apps without one, such as Delta Chat, take the file dragged from the window.
- README screenshots of the window, light and dark, from `scripts/snapshot.sh --readme`; `scripts/make-demo.sh` generates the photos, video and GIF in them.

## [0.2.1] - 2026-10-18

### Fixed

- The icon's shadows fall down, under the tile and the pouch; they were cast upward and showed as a dark band above the icon.

### Added

- `scripts/install.sh` installs the built DMG into Applications and restarts the Dock, so it does not keep a blank cached icon.

### Changed

- BUILD.md and README install with `scripts/install.sh`; `scripts/package.sh --open` stays for looking at the DMG and installing by hand.

## [0.2.0] - 2026-10-18

### Added

- About Vacpack links to the project and its author on GitHub and shows the commit the build came from and when it was pushed.
- Help menu: Vacpack on GitHub, Release Notes, Report an Issue, Author on GitHub.

### Changed

- The icon and the window share an old print poster's palette instead of neon blue, pink and violet: the icon's tile is mustard paper with a rust edge and its photo a cerulean sky with jade mountains; buttons, savings badges and progress are mustard printed in dark ink.
- File kinds take the photo's colors: cerulean for images, jade for videos, rust for GIF; "Original kept" is neutral gray.

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
