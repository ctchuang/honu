import Foundation

/// A microapp's items: a value for each, by id. It hands out ids in order,
/// lists the items in that order, and saves and loads them as a JSON array,
/// keeping their ids, so new ids come after restored ones.
struct ItemTable<Value> {
    /// Each item's value.
    private(set) var byID: [ItemID: Value] = [:]
    private var ids = ItemIDs()

    subscript(item: ItemID) -> Value? {
        byID[item]
    }

    /// Every item, oldest first.
    var items: [ItemID] { byID.keys.sorted() }

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

    /// The items, oldest first, as a JSON array of what `saved` makes of each.
    func save<Saved: Encodable>(_ saved: (ItemID, Value) -> Saved) -> Data? {
        try? JSONEncoder().encode(items.compactMap { id in byID[id].map { saved(id, $0) } })
    }

    /// Takes back the items `save` wrote, as `restored` makes them from each
    /// saved one. Anything unreadable is simply nothing to restore.
    mutating func load<Saved: Decodable>(
        _ data: Data, as type: Saved.Type, _ restored: (Saved) -> (ItemID, Value)
    ) {
        let saved = (try? JSONDecoder().decode([Saved].self, from: data)) ?? []
        for item in saved {
            let (id, value) = restored(item)
            ids.skip(past: id)
            byID[id] = value
        }
    }
}
