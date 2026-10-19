import SwiftUI

/// What one bubble showing a note keeps for itself.
@MainActor
final class NoteViewState: FocusTaking {
    /// Whether the text field should take the keyboard focus when next shown.
    var focusPending: Bool

    init(focusPending: Bool) {
        self.focusPending = focusPending
    }
}

/// Shows a note's text for editing.
struct NoteEditor: View {
    let app: NotesApp
    let item: ItemID
    let state: NoteViewState
    @FocusState private var focused: Bool

    var body: some View {
        let text = Binding(
            get: { app.notes[item] ?? "" },
            set: { app.setText($0, of: item) }
        )
        TextEditor(text: text)
            .font(.system(size: 16))
            .foregroundStyle(Color(white: 0.15))
            .scrollContentBackground(.hidden)
            .focused($focused)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text("Write something…")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(white: 0.15).opacity(0.45))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .takesFocus(state, $focused)
    }
}
