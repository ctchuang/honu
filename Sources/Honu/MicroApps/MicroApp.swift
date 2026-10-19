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

/// What a microapp keeps: its items, and how they are saved between launches.
@MainActor
protocol ItemStore: AnyObject {
    /// Starts a new item.
    func create() -> ItemID

    /// Deletes `item` for good.
    func remove(_ item: ItemID)

    /// Every item kept.
    var items: [ItemID] { get }

    /// The items as JSON, which `load` takes back on the next launch.
    func save() -> Data?

    /// Takes back the items `save` returned on a previous launch, keeping their ids.
    func load(_ data: Data)
}

/// How a microapp's items look on their bubbles, open or closed.
@MainActor
protocol ItemLook {
    func appearance(of item: ItemID) -> Appearance

    /// The label of the bubbles showing `item`.
    func title(of item: ItemID) -> String

    /// Whether `item` is being worked on, which makes its bubbles breathe.
    func isBusy(_ item: ItemID) -> Bool
}

extension ItemLook {
    func isBusy(_ item: ItemID) -> Bool { false }
}

/// What an open bubble shows of a microapp's item, and what each bubble
/// keeps for itself apart from the item's data.
@MainActor
protocol ItemViews {
    /// What one bubble keeps for itself, such as a draft or whether it still
    /// has to take the focus.
    associatedtype ViewState: AnyObject = NoViewState
    associatedtype Content: View

    /// The view state of one new bubble showing `item`. A `fresh` item was
    /// just created, as opposed to restored from a previous launch, so its
    /// bubble may take the focus.
    func newViewState(for item: ItemID, fresh: Bool) -> ViewState

    /// The content of an open bubble showing `item`, below its title.
    @ViewBuilder
    func content(of item: ItemID, viewState: ViewState) -> Content

    /// Takes `text`, typed for a new bubble showing `item` before its field
    /// could take the focus, for the field it shows first.
    func typeAhead(_ text: String, into item: ItemID, viewState: ViewState)
}

/// The view state of bubbles that keep nothing for themselves.
final class NoViewState {}

extension ItemViews {
    func typeAhead(_ text: String, into item: ItemID, viewState: ViewState) {}
}

extension ItemViews where ViewState == NoViewState {
    func newViewState(for item: ItemID, fresh: Bool) -> NoViewState { NoViewState() }
}

/// A microapp: it keeps its items (`ItemStore`), says how they look
/// (`ItemLook`), and makes the views that show them (`ItemViews`).
@MainActor
protocol MicroApp: ItemStore, ItemLook, ItemViews {
    var id: AppID { get }

    /// The turtle's menu item that starts a new item.
    var menuLabel: String { get }

    /// Catches up on work done in the background, asking things of the
    /// bubbles through `context`. Called every frame.
    func update(_ context: Context)
}

extension MicroApp {
    func update(_ context: Context) {}

    /// `content` for a view state the shell holds without its type. A bubble
    /// without one of the right type gets a new one, as a restored bubble would.
    func anyContent(of item: ItemID, viewState: AnyObject?) -> AnyView {
        let state = viewState as? ViewState ?? newViewState(for: item, fresh: false)
        return AnyView(content(of: item, viewState: state))
    }

    /// `typeAhead` for a view state the shell holds without its type.
    func anyTypeAhead(_ text: String, into item: ItemID, viewState: AnyObject?) {
        guard let state = viewState as? ViewState else { return }
        typeAhead(text, into: item, viewState: state)
    }
}

/// A bubble's view state whose field may still have to take the focus. Until
/// it does, text typed with no field focused goes to the bubble's microapp
/// (`MicroApp.typeAhead`), so no keystroke is lost while it flies out.
@MainActor
protocol FocusTaking: AnyObject {
    var focusPending: Bool { get set }
}
