import SwiftUI

// Microapps: Notes, Web, and whatever comes next. Each microapp keeps its own
// data (the model) and the logic around it (the controller). Bubbles on the
// desktop are only views: each one shows one item of one microapp and points
// at it by id, so a microapp can have any number of bubbles.

/// Names a microapp.
struct AppID: Hashable, Codable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// One item of a microapp's data, such as one note; unique within the app.
struct ItemID: Hashable, Comparable, Codable, Sendable {
    let rawValue: Int

    static func < (a: ItemID, b: ItemID) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// What a bubble shows: one item of one microapp.
struct ViewTarget: Hashable, Codable, Sendable {
    let app: AppID
    let item: ItemID
}

/// How the bubbles of a microapp's item look.
struct Appearance {
    /// The color the glass is tinted toward, if any.
    var tint: Color? = nil
    /// Shown on a closed bubble instead of its title.
    var symbol: String? = nil
    /// The side of a closed bubble.
    var closedSide: CGFloat = 88
    var panelSize = CGSize(width: 380, height: 300)
    var textColor: Color = .primary
}

/// Hands out a microapp's item ids.
struct ItemIDs {
    private var last = 0

    mutating func next() -> ItemID {
        last += 1
        return ItemID(rawValue: last)
    }

    /// Makes sure ids handed out from now on come after `id`, one restored
    /// from a previous launch.
    mutating func skip(past id: ItemID) {
        last = max(last, id.rawValue)
    }
}

/// A microapp: it keeps its items and makes the views that show them.
@MainActor
protocol MicroApp: AnyObject {
    var id: AppID { get }

    /// The turtle's menu item that starts a new item.
    var menuLabel: String { get }

    /// Starts a new item.
    func create() -> ItemID

    func appearance(of item: ItemID) -> Appearance

    /// The label of the bubbles showing `item`.
    func title(of item: ItemID) -> String

    /// What one new bubble showing `item` keeps for itself apart from the
    /// item's data, such as a draft or whether it still has to take the
    /// focus. A `fresh` item was just created, as opposed to restored from a
    /// previous launch, so its bubble may take the focus.
    func newViewState(for item: ItemID, fresh: Bool) -> AnyObject?

    /// The content of an open bubble showing `item`, below its title.
    func content(of item: ItemID, viewState: AnyObject?) -> AnyView

    /// Deletes `item` for good.
    func remove(_ item: ItemID)

    /// Every item kept.
    var items: [ItemID] { get }

    /// The items as JSON, which `load` takes back on the next launch.
    func save() -> Data?

    /// Takes back the items `save` returned on a previous launch, keeping their ids.
    func load(_ data: Data)
}

extension MicroApp {
    func newViewState(for item: ItemID, fresh: Bool) -> AnyObject? { nil }
}

/// The microapps, in the order the turtle's menu lists them.
@MainActor
final class Registry {
    let apps: [any MicroApp]

    init(_ apps: [any MicroApp]) {
        self.apps = apps
    }

    func app(_ id: AppID) -> (any MicroApp)? {
        apps.first { $0.id == id }
    }

    func title(of target: ViewTarget) -> String {
        app(target.app)?.title(of: target.item) ?? ""
    }

    /// Whether the microapp of `target` keeps its item.
    func has(_ target: ViewTarget) -> Bool {
        app(target.app)?.items.contains(target.item) ?? false
    }

    func remove(_ target: ViewTarget) {
        app(target.app)?.remove(target.item)
    }
}

/// Shortens `text` to a bubble label.
func shortLabel(_ text: String) -> String {
    let limit = 24
    guard text.count > limit else { return text }
    let label = text.prefix(limit).trimmingCharacters(in: .whitespaces)
    return label + "…"
}
