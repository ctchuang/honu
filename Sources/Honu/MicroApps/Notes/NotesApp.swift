import SwiftUI

/// The Notes microapp: any number of notes, each typed straight into its
/// bubble. A note's bubble takes its label from the note's first line, so
/// notes can be told apart.
@Observable
@MainActor
final class NotesApp: MicroApp {
    let id = AppID("notes")
    let launcherLabel = "Note"
    let launcherSymbol = "note.text"

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

    /// A note shows its title as its first line, so its bubble shows none
    /// above it.
    func appearance(of item: ItemID) -> Appearance {
        Appearance(tint: Self.yellow.opacity(0.75), textColor: Self.ink, showsTitle: false)
    }

    /// A short label for a note's bubble: its first line with anything on it.
    func title(of item: ItemID) -> String {
        guard let text = notes[item], let line = Self.titleLine(of: text) else {
            return Self.emptyLabel
        }
        return shortLabel(text[line].trimmingCharacters(in: .whitespaces))
    }

    /// Where a note's title is: its first line with anything on it.
    static func titleLine(of text: String) -> Range<String.Index>? {
        var start = text.startIndex
        while start < text.endIndex {
            let end = text[start...].firstIndex(where: \.isNewline) ?? text.endIndex
            if text[start..<end].contains(where: { !$0.isWhitespace }) {
                return start..<end
            }
            start = end == text.endIndex ? end : text.index(after: end)
        }
        return nil
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
