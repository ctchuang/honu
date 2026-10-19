import AppKit
import SwiftUI

/// Shows `content` with an undo history of its own. Text views and web
/// pages find their undo manager up the responder chain, and a window has
/// only one, so without a scope every bubble would share it: ⌘Z would undo
/// the last edit in any bubble, not in the one with the focus. SwiftUI's
/// `undoManager` cannot be set, and its text views keep the one they first
/// found, so the scope is a view in the chain, hosting the content.
struct UndoScope<Content: View>: NSViewRepresentable {
    let history: UndoManager
    let content: Content

    func makeNSView(context: NSViewRepresentableContext<Self>) -> ScopeView<Content> {
        ScopeView(history: history, content: content)
    }

    func updateNSView(_ view: ScopeView<Content>, context: NSViewRepresentableContext<Self>) {
        view.history = history
        view.hosting.rootView = content
    }
}

/// The view `UndoScope` puts in the responder chain. It also undoes and
/// redoes for web pages, which leave that to the next responder.
final class ScopeView<Content: View>: NSView, NSMenuItemValidation {
    var history: UndoManager
    let hosting: NSHostingView<Content>

    init(history: UndoManager, content: Content) {
        self.history = history
        hosting = NSHostingView(rootView: content)
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var undoManager: UndoManager? { history }

    @objc func undo(_ sender: Any?) {
        history.undo()
    }

    @objc func redo(_ sender: Any?) {
        history.redo()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): history.canUndo
        case #selector(redo(_:)): history.canRedo
        default: true
        }
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }
}
