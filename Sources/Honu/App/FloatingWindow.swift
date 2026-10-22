import AppKit
import SwiftUI

/// A transparent, borderless window that shows the stage of bubbles directly
/// on the desktop. It sits at the normal window level, behind the other
/// apps' windows while they are in use (`sendBack`), and comes to the front
/// when Honu does.
final class FloatingWindow: NSWindow {
    init(frame: NSRect, content: some View) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isOnAllDesktops = false
        isReleasedWhenClosed = false

        let hosting = FirstClickHostingView(rootView: content)
        // Keep the window the size of the screen instead of the content's ideal size.
        hosting.sizingOptions = []
        contentView = hosting
        setFrame(frame, display: true)
    }

    /// Whether the window shows on every desktop (Space). Otherwise it stays
    /// on the one Honu was launched on. Either way it is transient, so
    /// Mission Control and App Exposé hide it rather than lay out a window
    /// the size of the screen over the others, and it never goes full screen
    /// (as Fn-F or Control-Command-F would make the key window do), since it
    /// already covers the screen beside other apps.
    ///
    /// Mission Control's Space thumbnails leave out every window that lies
    /// wholly inside one above them, as if it were opaque, so Honu's window
    /// must be behind the others there (issue #5); see `sendBack`.
    var isOnAllDesktops: Bool {
        get { collectionBehavior.contains(.canJoinAllSpaces) }
        set {
            collectionBehavior = [.transient, .fullScreenNone]
            if newValue {
                collectionBehavior.insert(.canJoinAllSpaces)
            }
        }
    }

    /// Puts the window behind every other window, where it shows only where
    /// the desktop does, as it should while another app is in use.
    func sendBack() {
        orderBack(nil)
    }

    /// Brings the window in front of the others, as it should while Honu is
    /// in use.
    func bringFront() {
        orderFront(nil)
    }

    // Borderless windows refuse key status by default, but web pages need it for typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A hosting view whose first click acts, rather than only bringing Honu to
/// the front, so a bubble or the turtle behind another app's windows can be
/// dragged or clicked at once.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
