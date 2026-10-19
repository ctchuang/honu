import SwiftUI

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
