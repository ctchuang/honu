import SwiftUI

/// A bubble's view state whose field takes the focus when the bubble first
/// shows a new item, and again each time the item asks for it, as when the
/// user has to type again after a failure: once per request, in every view.
@MainActor
final class FocusRequestState: FocusTaking {
    /// Whether the next text field shown should take the keyboard focus.
    var focusPending: Bool
    /// The item's `focusRequests` this view has answered.
    private var focusRequestsSeen = 0

    init(focusPending: Bool) {
        self.focusPending = focusPending
    }

    /// Notes any new request of the item for the focus, and returns whether
    /// the field shown now should take it, which it then does.
    func focusDue(after focusRequests: Int) -> Bool {
        if focusRequestsSeen != focusRequests {
            focusRequestsSeen = focusRequests
            focusPending = true
        }
        defer { focusPending = false }
        return focusPending
    }
}

extension View {
    /// Gives the field bound to `focused` the keyboard focus when the view
    /// appears, if its bubble's `state` still has to take it, and only once.
    func takesFocus(_ state: some FocusTaking, _ focused: FocusState<Bool>.Binding) -> some View {
        onAppear {
            guard state.focusPending else { return }
            state.focusPending = false
            focused.wrappedValue = true
            placeCursorAtEnd()
        }
    }

    /// Gives the field bound to `focused` the keyboard focus once per request
    /// of the item for it, which `requests` counts, as `state` says is due.
    func takesFocus(
        _ state: FocusRequestState, requests: Int, _ focused: FocusState<Bool>.Binding
    ) -> some View {
        let take = { (requests: Int) in
            guard state.focusDue(after: requests) else { return }
            focused.wrappedValue = true
            placeCursorAtEnd()
        }
        return onAppear { take(requests) }
            .onChange(of: requests) { _, requests in take(requests) }
    }
}

/// Puts the cursor at the end of the text in the field that just took the
/// focus, rather than selecting it all, so typing carries on where it stops.
@MainActor
func placeCursorAtEnd() {
    Task { @MainActor in
        // The focus moves to the field once SwiftUI has updated.
        try? await Task.sleep(for: .milliseconds(30))
        guard let text = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
    }
}
