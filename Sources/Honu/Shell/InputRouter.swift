import Foundation

/// An event SwiftUI's gestures do not cover, as `InputRouter` takes it,
/// apart from AppKit, so the rules can be tested without it.
enum InputEvent: Equatable {
    /// A press, including one on content AppKit views take for themselves.
    case press(at: CGPoint)
    case rightPress(at: CGPoint)
    case escape
    /// A key: what it types, what it would type without modifiers, and
    /// which modifiers are held.
    case key(text: String, unmodified: String, command: Bool, control: Bool)
}

/// Turns the events SwiftUI's gestures do not cover into calls on the shell:
/// presses on content (raising that bubble), right-clicks on the turtle
/// (opening its menu), Escape (closing it), text typed while no field has
/// the focus (type-ahead), and ⌘Z (undoing a delete).
@MainActor
struct InputRouter {
    let shell: Shell

    /// Handles `event`, given whether a text field has the keyboard focus.
    /// Returns whether it did, in which case the event goes no further.
    func handle(_ event: InputEvent, typing: Bool) -> Bool {
        switch event {
        case .press(let point):
            // Only noted: the press still goes on to whatever is under it.
            shell.press(at: point)
            return false
        case .rightPress(let point):
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
            return false
        case .escape:
            guard shell.menu != nil else { return false }
            shell.closeMenu()
            return true
        case .key(let text, let unmodified, let command, let control):
            // Text typed while no field has the focus goes to the newest bubble,
            // whose field takes it once the bubble lands and opens.
            if !typing, !command, !control, Self.isPrintable(text), shell.type(text) {
                return true
            }
            // ⌘Z undoes a delete, unless a text field wants it.
            if command, unmodified == "z", !typing, shell.octopus.canUndo {
                shell.undoDelete()
                return true
            }
            return false
        }
    }

    /// Whether `text` is something typed to write, rather than a key such as
    /// Return, Delete, or an arrow.
    static func isPrintable(_ text: String) -> Bool {
        !text.isEmpty
            && text.unicodeScalars.allSatisfy {
                ![.control, .privateUse, .unassigned].contains($0.properties.generalCategory)
            }
    }
}
