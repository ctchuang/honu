import AppKit
import QuartzCore

/// Calls `onFrame` once for every frame the window's display draws, so the
/// shell catches up as often as the screen refreshes (60 or 120 times a
/// second). It keeps running while the pointer drags or a menu tracks, which
/// a timer in the default run loop mode would not.
@MainActor
final class FrameClock: NSObject {
    private let onFrame: () -> Void
    private var link: CADisplayLink?

    init(window: NSWindow, onFrame: @escaping () -> Void) {
        self.onFrame = onFrame
        super.init()
        let link = window.displayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        onFrame()
    }
}
