import AppKit

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
