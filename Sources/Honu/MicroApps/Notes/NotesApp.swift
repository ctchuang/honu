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
    private(set) var notes = ItemTable<String>()

    /// The label of a note with nothing written in it yet.
    static let emptyLabel = "Note"
    /// The pale yellow of a sticky note.
    static let yellow = Color(red: 1, green: 0.925, blue: 0.59)
    /// The dark gray a note is written in, on its yellow glass.
    static let ink = Color(white: 0.15)

    func create() -> ItemID {
        notes.insert("")
    }

    func appearance(of item: ItemID) -> Appearance {
        Appearance(
            tint: Self.yellow.opacity(0.75),
            closedSide: 120,
            textColor: Self.ink
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
    func newViewState(for item: ItemID, fresh: Bool) -> NoteViewState {
        NoteViewState(focusPending: fresh)
    }

    func content(of item: ItemID, viewState: NoteViewState) -> NoteEditor {
        NoteEditor(app: self, item: item, state: viewState)
    }

    /// Text typed before the note's field took the focus goes at its end.
    func typeAhead(_ text: String, into item: ItemID, viewState: NoteViewState) {
        setText((notes[item] ?? "") + text, of: item)
    }

    func setText(_ text: String, of item: ItemID) {
        notes.update(item, to: text)
    }

    func remove(_ item: ItemID) {
        notes.remove(item)
    }

    var items: [ItemID] { notes.items }

    private struct SavedNote: Codable {
        var id: ItemID
        var text: String
    }

    func save() -> Data? {
        notes.save { SavedNote(id: $0, text: $1) }
    }

    func load(_ data: Data) {
        notes.load(data, as: SavedNote.self) { ($0.id, $0.text) }
    }
}
