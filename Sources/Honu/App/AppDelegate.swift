import AppKit
import SwiftUI

/// Sets up the menu bar and the floating window that covers the screen, and
/// passes the input SwiftUI's gestures do not cover to an `InputRouter`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: FloatingWindow?
    private var shell: Shell?
    private var frameClock: FrameClock?
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
        let clickThrough = ClickThrough(window: window, shell: shell)
        frameClock = FrameClock(window: window) {
            shell.tick()
            clickThrough.update()
        }
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

    /// Hands the shell, through an `InputRouter`, what SwiftUI's gestures do
    /// not cover. Returns whether it was handled, and then goes no further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let shell, let window, event.window === window,
            let input = Self.input(event, in: window)
        else { return false }
        let typing = window.firstResponder is NSText
        return InputRouter(shell: shell).handle(input, typing: typing)
    }

    /// `event` as the input router takes it, if it is one it handles.
    private static func input(_ event: NSEvent, in window: NSWindow) -> InputEvent? {
        // SwiftUI measures from the top-left corner, AppKit from the bottom-left.
        let height = window.contentView?.bounds.height ?? 0
        let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
        switch event.type {
        case .leftMouseDown:
            return .press(at: point)
        case .rightMouseDown:
            return .rightPress(at: point)
        case .keyDown where event.keyCode == 53:
            return .escape
        case .keyDown:
            return .key(
                text: event.characters ?? "",
                unmodified: event.charactersIgnoringModifiers ?? "",
                command: event.modifierFlags.contains(.command),
                control: event.modifierFlags.contains(.control))
        default:
            return nil
        }
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
