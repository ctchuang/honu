import Foundation
import SwiftUI
import Testing

@testable import Honu

/// A microapp whose items are counters.
@MainActor
private final class Counters: MicroApp {
    let id = AppID("counters")
    let launcherLabel = "Count"
    let launcherSymbol = "number"
    var counts: [ItemID: Int] = [:]
    private var ids = ItemIDs()

    func create() -> ItemID {
        let id = ids.next()
        counts[id] = 0
        return id
    }

    func appearance(of item: ItemID) -> Appearance { Appearance() }

    func title(of item: ItemID) -> String {
        counts[item].map(String.init) ?? ""
    }

    func content(of item: ItemID, viewState: NoViewState) -> EmptyView { EmptyView() }

    func remove(_ item: ItemID) {
        counts[item] = nil
    }

    var items: [ItemID] { counts.keys.sorted() }

    func save() -> Data? {
        try? JSONEncoder().encode(items.map { [$0.rawValue, counts[$0] ?? 0] })
    }

    func load(_ data: Data) {
        let saved = (try? JSONDecoder().decode([[Int]].self, from: data)) ?? []
        for pair in saved where pair.count == 2 {
            let id = ItemID(rawValue: pair[0])
            ids.skip(past: id)
            counts[id] = pair[1]
        }
    }
}

@MainActor
struct MicroAppTests {
    @Test func restoredItemsKeepTheirIdsAndNewOnesComeAfter() throws {
        let counters = Counters()
        let a = counters.create()
        let b = counters.create()
        counters.counts[b] = 5
        let restored = Counters()
        restored.load(try #require(counters.save()))
        #expect(restored.items == [a, b])
        #expect(restored.title(of: b) == "5")
        #expect(restored.create() > b, "reused a restored id")
    }

    @Test func registryRoutesToTheMicroappOfEachTarget() {
        let counters = Counters()
        let registry = Registry([counters])
        #expect(registry.apps.map(\.launcherLabel) == ["Count"])

        let target = ViewTarget(app: counters.id, item: counters.create())
        #expect(registry.title(of: target) == "0")
        #expect(registry.has(target))

        registry.remove(target)
        #expect(registry.title(of: target) == "")
        #expect(!registry.has(target))

        let unknown = ViewTarget(app: AppID("unknown"), item: target.item)
        #expect(registry.app(unknown.app) == nil)
        #expect(registry.title(of: unknown) == "")
    }

    @Test func aViewStateOfAnotherTypeIsNeitherTypedIntoNorShown() {
        let notes = NotesApp()
        let item = notes.create()
        notes.anyTypeAhead("lost", into: item, viewState: NoViewState())
        notes.anyTypeAhead("lost", into: item, viewState: nil)
        #expect(notes.notes[item] == "")
        notes.anyTypeAhead(
            "kept", into: item, viewState: notes.newViewState(for: item, fresh: true))
        #expect(notes.notes[item] == "kept")
        // Content for a bubble without the right view state still shows the note.
        _ = notes.anyContent(of: item, viewState: nil)
    }

    @Test func anItemTableKeepsIdsInOrderAndSavesThemAsBefore() throws {
        var table = ItemTable<String>()
        let a = table.insert("a")
        let b = table.insert("b")
        table.remove(a)
        table.update(a, to: "gone")
        #expect(table.items == [b])
        #expect(table[a] == nil, "a removed item came back")

        // Saved as a JSON array, one object per item with its id, as the
        // microapps always saved them.
        struct Saved: Codable, Equatable {
            var id: ItemID
            var text: String
        }
        let data = try #require(table.save { Saved(id: $0, text: $1) })
        let json = try #require(Autosave.canonical(data))
        #expect(String(decoding: json, as: UTF8.self) == #"[{"id":{"rawValue":2},"text":"b"}]"#)
        var restored = ItemTable<String>()
        restored.load(data, as: Saved.self) { ($0.id, $0.text) }
        #expect(restored[b] == "b")
        #expect(restored.insert("c") > b, "reused a restored id")
    }

    @Test func longTextGetsAShortLabel() {
        #expect(shortLabel("Groceries") == "Groceries")
        #expect(shortLabel(String(repeating: "a", count: 24)) == String(repeating: "a", count: 24))
        #expect(shortLabel("Remember to call the aquarium") == "Remember to call the aqu…")
        // No space is left before the ellipsis.
        #expect(shortLabel("Remember to call the     aquarium") == "Remember to call the…")
    }
}
