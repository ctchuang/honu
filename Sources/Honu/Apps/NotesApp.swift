import SwiftUI

/// The Notes microapp: any number of notes, each typed straight into its
/// bubble. A note's bubble takes its label from the note's first line, so
/// closed notes can be told apart.
@Observable
@MainActor
final class NotesApp: MicroApp {
    let id = AppID("notes")
    let menuLabel = "Add Note"

    /// The model: each note's text.
    private(set) var notes: [ItemID: String] = [:]
    @ObservationIgnored private var ids = ItemIDs()

    /// The label of a note with nothing written in it yet.
    static let emptyLabel = "Note"
    /// The pale yellow of a sticky note.
    static let yellow = Color(red: 1, green: 0.925, blue: 0.59)

    func create() -> ItemID {
        let id = ids.next()
        notes[id] = ""
        return id
    }

    func appearance(of item: ItemID) -> Appearance {
        Appearance(
            tint: Self.yellow.opacity(0.75),
            closedSide: 120,
            textColor: Color(white: 0.15)
        )
    }

    /// A short label for a note's bubble: its first line with anything on it.
    func title(of item: ItemID) -> String {
        let line = notes[item]?
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line.map(shortLabel) ?? Self.emptyLabel
    }

    /// A new note is for writing in, so its bubble starts with the cursor in it.
    func newViewState(for item: ItemID, fresh: Bool) -> AnyObject? {
        NoteViewState(focusPending: fresh)
    }

    func content(of item: ItemID, viewState: AnyObject?) -> AnyView {
        AnyView(NoteEditor(app: self, item: item, state: viewState as? NoteViewState))
    }

    func setText(_ text: String, of item: ItemID) {
        guard notes[item] != nil else { return }
        notes[item] = text
    }

    func remove(_ item: ItemID) {
        notes[item] = nil
    }

    var items: [ItemID] { notes.keys.sorted() }

    private struct SavedNote: Codable {
        var id: ItemID
        var text: String
    }

    func save() -> Data? {
        try? JSONEncoder().encode(items.map { SavedNote(id: $0, text: notes[$0] ?? "") })
    }

    func load(_ data: Data) {
        // Anything unreadable is simply nothing to restore.
        let saved = (try? JSONDecoder().decode([SavedNote].self, from: data)) ?? []
        for note in saved {
            ids.skip(past: note.id)
            notes[note.id] = note.text
        }
    }
}

/// What one bubble showing a note keeps for itself.
@MainActor
final class NoteViewState {
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
    let state: NoteViewState?
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
            .onAppear {
                if let state, state.focusPending {
                    state.focusPending = false
                    focused = true
                }
            }
    }
}
