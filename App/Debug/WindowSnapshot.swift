#if DEBUG
    import AppKit

    /// Debug only: `VACPACK_SNAPSHOT=<file.png>` renders the main window into a PNG and quits, so the
    /// design can be reviewed without screen recording (`scripts/snapshot.sh`). The window stays
    /// transparent on screen while this runs.
    @MainActor
    enum WindowSnapshot {
        /// Snapshots cannot capture scroll views (macOS 26 builds them from backdrop and portal
        /// layers), so lists lay out without scrolling while one is being taken.
        static let isActive = ProcessInfo.processInfo.environment["VACPACK_SNAPSHOT"] != nil

        /// Called at launch: controls created before an appearance change keep the old colors.
        static func applyAppearance() {
            switch ProcessInfo.processInfo.environment["VACPACK_SNAPSHOT_APPEARANCE"] {
            case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
            case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
            default: break
            }
        }

        static func runIfRequested(isBusy: @escaping @MainActor () -> Bool) {
            let environment = ProcessInfo.processInfo.environment
            guard let path = environment["VACPACK_SNAPSHOT"] else { return }
            for window in NSApp.windows { window.alphaValue = 0 }
            Task {
                try? await Task.sleep(for: .seconds(1))
                guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else { exit(1) }
                window.alphaValue = 0
                window.setContentSize(NSSize(width: 900, height: 780))
                // Wait for a requested run to finish, then for thumbnails.
                for _ in 0..<240 where isBusy() { try? await Task.sleep(for: .milliseconds(250)) }
                try? await Task.sleep(for: .seconds(1.5))
                // Render the layer tree; the frame view's layer includes the title bar.
                guard let view = window.contentView?.superview ?? window.contentView, let layer = view.layer,
                    let image = render(layer, size: view.bounds.size, scale: window.backingScaleFactor)
                else { exit(1) }
                do {
                    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                        .write(to: URL(filePath: path))
                } catch {
                    exit(1)
                }
                NSApp.terminate(nil)
            }
        }

        private static func render(_ layer: CALayer, size: CGSize, scale: CGFloat) -> CGImage? {
            guard
                let context = CGContext(
                    data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
            else { return nil }
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
            return context.makeImage()
        }
    }
#endif
