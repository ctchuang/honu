import Foundation

/// A microapp's items: a value for each, by id. It hands out ids in order,
/// lists the items in that order, and saves and loads them as a JSON array,
/// keeping their ids, so new ids come after restored ones.
struct ItemTable<Value> {
    /// Each item's value.
    private var byID: [ItemID: Value] = [:]
    private var ids = ItemIDs()

    subscript(item: ItemID) -> Value? {
        byID[item]
    }

    /// Every item, oldest first.
    var items: [ItemID] { byID.keys.sorted() }

    /// Every item with its value, oldest first, so what is done with each
    /// happens in the same order every time.
    var entries: [(id: ItemID, value: Value)] {
        byID.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Adds an item holding `value`, returning its id.
    mutating func insert(_ value: Value) -> ItemID {
        let id = ids.next()
        byID[id] = value
        return id
    }

    /// Replaces the value of `item`, if there is one; a removed item stays removed.
    mutating func update(_ item: ItemID, to value: Value) {
        guard byID[item] != nil else { return }
        byID[item] = value
    }

    mutating func remove(_ item: ItemID) {
        byID[item] = nil
    }

    /// Puts back `item`, one restored from a previous launch, holding `value`.
    mutating func restore(_ item: ItemID, _ value: Value) {
        ids.skip(past: item)
        byID[item] = value
    }

    /// The items, oldest first, as a JSON array of what `saved` makes of each.
    func save<Saved: Encodable>(_ saved: (ItemID, Value) -> Saved) -> Data? {
        try? JSONEncoder().encode(entries.map { saved($0.id, $0.value) })
    }

    /// Takes back the items `save` wrote, as `restored` makes them from each
    /// saved one. Anything unreadable is simply nothing to restore.
    mutating func load<Saved: Decodable>(
        _ data: Data, as type: Saved.Type, _ restored: (Saved) -> (ItemID, Value)
    ) {
        let saved = (try? JSONDecoder().decode([Saved].self, from: data)) ?? []
        for item in saved {
            let (id, value) = restored(item)
            restore(id, value)
        }
    }
}
