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

/// Something a microapp asks of the bubbles showing its items.
enum Effect: Equatable {
    /// Every bubble showing the target plays the motion.
    case motion(ViewTarget, Motion)
}

/// What a microapp gets to work with while it catches up: a way to ask
/// things of the bubbles showing its items.
@MainActor
final class Context {
    let app: AppID
    private(set) var effects: [Effect] = []

    init(app: AppID) {
        self.app = app
    }

    /// Has every bubble showing `item` play `motion`.
    func play(_ motion: Motion, for item: ItemID) {
        effects.append(.motion(ViewTarget(app: app, item: item), motion))
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

    /// Whether `item` is being worked on, which makes its bubbles breathe.
    func isBusy(_ item: ItemID) -> Bool

    /// Catches up on work done in the background, asking things of the
    /// bubbles through `context`. Called many times a second.
    func update(_ context: Context)

    /// What one new bubble showing `item` keeps for itself apart from the
    /// item's data, such as a draft or whether it still has to take the
    /// focus. A `fresh` item was just created, as opposed to restored from a
    /// previous launch, so its bubble may take the focus.
    func newViewState(for item: ItemID, fresh: Bool) -> AnyObject?

    /// Takes `text`, typed for a new bubble showing `item` before its field
    /// could take the focus, for the field it shows first.
    func typeAhead(_ text: String, into item: ItemID, viewState: AnyObject?)

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
    func isBusy(_ item: ItemID) -> Bool { false }
    func update(_ context: Context) {}
    func newViewState(for item: ItemID, fresh: Bool) -> AnyObject? { nil }
    func typeAhead(_ text: String, into item: ItemID, viewState: AnyObject?) {}
}

/// A bubble's view state whose field may still have to take the focus. Until
/// it does, text typed with no field focused goes to the bubble's microapp
/// (`MicroApp.typeAhead`), so no keystroke is lost while it flies out.
@MainActor
protocol FocusTaking: AnyObject {
    var focusPending: Bool { get }
}

/// Puts the cursor at the end of the text in the field that just took the
/// focus, rather than selecting it all, so typing carries on where it stops.
@MainActor
func placeCursorAtEnd() {
    Task { @MainActor in
        // The focus moves to the field once SwiftUI has updated.
        try? await Task.sleep(for: .milliseconds(30))
        guard let text = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
    }
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

    func isBusy(_ target: ViewTarget) -> Bool {
        app(target.app)?.isBusy(target.item) ?? false
    }

    /// Lets every microapp catch up, returning what they ask of their bubbles.
    func update() -> [Effect] {
        apps.flatMap { app in
            let context = Context(app: app.id)
            app.update(context)
            return context.effects
        }
    }
}

/// Shortens `text` to a bubble label.
func shortLabel(_ text: String) -> String {
    let limit = 24
    guard text.count > limit else { return text }
    let label = text.prefix(limit).trimmingCharacters(in: .whitespaces)
    return label + "…"
}
