import AppKit
import SwiftUI

/// Sets up the menu bar and the floating window that covers the screen, and
/// hands the shell the input SwiftUI's gestures do not cover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: FloatingWindow?
    private var shell: Shell?
    private var clickThrough: ClickThrough?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.module.url(forResource: "icon", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        NSApp.mainMenu = makeMainMenu()

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let shell = Shell(size: frame.size)
        let window = FloatingWindow(frame: frame, content: ShellView(shell: shell))
        window.makeKeyAndOrderFront(nil)
        clickThrough = ClickThrough(window: window, shell: shell)
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
        self.window = window
        self.shell = shell
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shell?.save()
    }

    /// Handles what SwiftUI's gestures do not: presses on content that
    /// AppKit views take for themselves, right-clicks, Escape, and ⌘Z.
    /// Returns whether it handled the event, which then goes no further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let shell, let window, event.window === window else { return false }
        // SwiftUI measures from the top-left corner, AppKit from the bottom-left.
        let height = window.contentView?.bounds.height ?? 0
        let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
        switch event.type {
        case .leftMouseDown:
            shell.press(at: point)
        case .rightMouseDown:
            // Right-clicking the turtle opens its menu as clicking does;
            // right-clicking anywhere else closes it.
            if shell.turtle.contains(point) {
                shell.clickTurtle(at: point)
                return true
            }
            if shell.menu != nil {
                shell.closeMenu()
                return true
            }
        case .keyDown:
            if event.keyCode == 53, shell.menu != nil {  // Escape
                shell.closeMenu()
                return true
            }
            // ⌘Z undoes a delete, unless a text field wants it.
            let typing = window.firstResponder is NSText
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z",
                !typing, shell.octopus.canUndo
            {
                shell.undoDelete()
                return true
            }
        default:
            break
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Honu",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let menu = NSMenu()
        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }
}
