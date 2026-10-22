import AppKit
import SwiftUI

/// A transparent, borderless window that floats above other windows and
/// shows the stage of bubbles directly on the desktop.
final class FloatingWindow: NSWindow {
    init(frame: NSRect, content: some View) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isOnAllDesktops = false
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: content)
        // Keep the window the size of the screen instead of the content's ideal size.
        hosting.sizingOptions = []
        contentView = hosting
        setFrame(frame, display: true)
    }

    /// Whether the window shows on every desktop (Space). Otherwise it stays
    /// on the one Honu was launched on, like an ordinary window. Either way
    /// it never goes full screen (as Fn-F or Control-Command-F would make the
    /// key window do), since it already covers the screen beside other apps.
    var isOnAllDesktops: Bool {
        get { collectionBehavior.contains(.canJoinAllSpaces) }
        set { collectionBehavior = [newValue ? .canJoinAllSpaces : .managed, .fullScreenNone] }
    }

    // Borderless windows refuse key status by default, but web pages need it for typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Lets clicks through to the apps below everywhere except on something of
/// Honu's. Call `update` every frame.
///
/// A window that ignores mouse events gets none, so the global mouse position
/// is polled to decide when to start taking them again.
@MainActor
final class ClickThrough {
    private weak var window: NSWindow?
    private let shell: Shell

    init(window: NSWindow, shell: Shell) {
        self.window = window
        self.shell = shell
    }

    func update() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        // SwiftUI measures from the top-left corner, AppKit from the bottom-left.
        let point = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let takes = shell.takesClick(at: point)
        if window.ignoresMouseEvents == takes {
            window.ignoresMouseEvents = !takes
        }
    }
}
