import Foundation
import SwiftUI
import Testing

@testable import Honu

/// A microapp whose items are counters.
@MainActor
private final class Counters: MicroApp {
    let id = AppID("counters")
    let menuLabel = "Count"
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

    func content(of item: ItemID, viewState: AnyObject?) -> AnyView { AnyView(EmptyView()) }

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
        #expect(registry.apps.map(\.menuLabel) == ["Count"])

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

    @Test func longTextGetsAShortLabel() {
        #expect(shortLabel("Groceries") == "Groceries")
        #expect(shortLabel(String(repeating: "a", count: 24)) == String(repeating: "a", count: 24))
        #expect(shortLabel("Remember to call the aquarium") == "Remember to call the aqu…")
        // No space is left before the ellipsis.
        #expect(shortLabel("Remember to call the     aquarium") == "Remember to call the…")
    }
}
