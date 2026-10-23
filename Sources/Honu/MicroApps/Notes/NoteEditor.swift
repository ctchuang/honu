import SwiftUI

/// What one bubble showing a note keeps for itself.
@MainActor
final class NoteViewState: FocusTaking {
    /// Whether the text field should take the keyboard focus when next shown.
    var focusPending: Bool
    /// The note's text as this bubble's editor shows it, its title styled.
    private var shownText = AttributedString()
    /// Where the cursor is in `shownText`.
    var selection = AttributedTextSelection()

    init(focusPending: Bool) {
        self.focusPending = focusPending
    }

    /// The note's text styled for the editor, kept from the last edit while
    /// the text is the same, so the editor keeps its cursor.
    func shown(_ note: String) -> AttributedString {
        if String(shownText.characters) != note {
            shownText = AttributedString(note)
            NoteEditor.style(&shownText)
        }
        return shownText
    }

    /// Takes the editor's text, restyles it since its title line may have
    /// changed, and returns it plain, as the note keeps it.
    func edited(_ text: AttributedString) -> String {
        var text = text
        text.transform(updating: &selection) { NoteEditor.style(&$0) }
        shownText = text
        return String(text.characters)
    }
}

/// Shows a note's text for editing, its title (the first line with text, which
/// labels its bubble) set larger than the rest.
struct NoteEditor: View {
    let app: NotesApp
    let item: ItemID
    let state: NoteViewState
    @FocusState private var focused: Bool

    static let bodyFont = Font.system(size: 16)
    static let titleFont = Font.system(size: 20, weight: .bold)

    /// The only attribute a note's text has: the font, which sets its title
    /// apart. Formatting pasted in, or typed with ⌘B and the like, is dropped.
    struct Attributes: AttributeScope {
        let font: AttributeScopes.SwiftUIAttributes.FontAttribute
    }

    /// Sets a note's title line in `titleFont`, and the rest in the body font.
    static func style(_ text: inout AttributedString) {
        text.font = nil
        let plain = String(text.characters)
        guard let line = NotesApp.titleLine(of: plain) else { return }
        let start = text.characters.index(
            text.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: line.lowerBound))
        let end = text.characters.index(start, offsetBy: plain[line].count)
        text[start..<end].font = titleFont
    }

    var body: some View {
        let text = Binding(
            get: { state.shown(app.notes[item] ?? "") },
            set: { app.setText(state.edited($0), of: item) }
        )
        let selection = Binding(get: { state.selection }, set: { state.selection = $0 })
        TextEditor(text: text, selection: selection)
            .font(Self.bodyFont)
            .attributedTextFormattingDefinition(Attributes.self)
            .foregroundStyle(NotesApp.ink)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .overlay(alignment: .topLeading) {
                if app.notes[item]?.isEmpty ?? true {
                    Text("Write something…")
                        .font(Self.titleFont)
                        .foregroundStyle(NotesApp.ink.opacity(0.45))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .takesFocus(state, $focused)
    }
}
