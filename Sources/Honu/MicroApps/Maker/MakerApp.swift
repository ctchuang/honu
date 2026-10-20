import AppKit
import SwiftUI

/// The Maker microapp: any number of microapps Claude writes. In a new one's
/// bubble you describe what you want; Claude writes a web page that does it,
/// which then runs in the bubble, and which you can ask Claude to change.
/// Each microapp keeps its page, and what the page saves, in a folder of its
/// own.
@Observable
@MainActor
final class MakerApp: MicroApp {
    let id = AppID("maker")
    let menuLabel = "Make a Microapp"

    /// The label of a microapp not yet described.
    static let emptyLabel = "Microapp"
    /// The closed bubble's symbol when the page names none, or none that exists.
    static let defaultSymbol = "sparkles"
    /// The size of a page that says nothing of its size.
    static let defaultPageSize = CGSize(width: 360, height: 480)
    /// The panel while asking for a description, and while the page is written.
    static let describingSize = CGSize(width: 420, height: 190)
    static let writingSize = CGSize(width: 440, height: 320)
    /// Panel size not taken by the page: the title bar, margins, and the bar
    /// for asking for changes.
    static let chrome = CGSize(width: 20, height: 46 + ChangeBar.height)

    /// Where the microapps' folders are.
    let root: URL
    /// The model: each microapp.
    private(set) var microapps = ItemTable<GeneratedApp>()
    @ObservationIgnored let services: Services
    /// Microapps whose new page has loaded since the last `update`, whose
    /// bubbles rise.
    @ObservationIgnored private var risen: Set<ItemID> = []

    init(root: URL, services: Services) {
        self.root = root
        self.services = services
    }

    /// Where the microapps of the store at `storeURL` are kept: `microapps/`
    /// beside Honu's own store, or `<name>.microapps/` beside another.
    static func root(for storeURL: URL) -> URL {
        if storeURL == Autosave.defaultURL {
            return Services.folder.appending(path: "microapps", directoryHint: .isDirectory)
        }
        return storeURL.deletingPathExtension().appendingPathExtension("microapps")
    }

    private func folder(named name: String) -> AppFolder {
        AppFolder(url: root.appending(path: name, directoryHint: .isDirectory))
    }

    /// Starts a microapp with nothing described yet. Its folder is made when
    /// its first page is written.
    func create() -> ItemID {
        microapps.insert(GeneratedApp(folder: folder(named: UUID().uuidString)))
    }

    func appearance(of item: ItemID) -> Appearance {
        guard let microapp = microapps[item] else { return Appearance() }
        let symbol = microapp.meta.symbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0
        }
        let panel: CGSize =
            switch microapp.status {
            case .describing: Self.describingSize
            case .writing(.making): Self.writingSize
            case .writing, .running:
                (microapp.size ?? Self.defaultPageSize) + Self.chrome
            }
        return Appearance(symbol: symbol ?? Self.defaultSymbol, panelSize: panel)
    }

    func title(of item: ItemID) -> String {
        guard let microapp = microapps[item] else { return Self.emptyLabel }
        return shortLabel(microapp.meta.title ?? microapp.description ?? Self.emptyLabel)
    }

    /// Whether Claude is writing a microapp's page.
    func isBusy(_ item: ItemID) -> Bool {
        microapps[item]?.isBusy ?? false
    }

    /// Takes in what Claude has written, and fixes pages' errors when due.
    /// A microapp's bubbles wobble when writing fails, and rise when a new
    /// page has loaded.
    func update(_ context: Context) {
        let time = now()
        for (item, microapp) in microapps.byID.sorted(by: { $0.key < $1.key }) {
            if microapp.poll(services.claude, at: time) == .needsAttention {
                context.play(.wobble, for: item)
            }
        }
        for item in risen.sorted() {
            context.play(.rise, for: item)
        }
        risen.removeAll()
    }

    /// A new microapp is to be described, so its bubble starts with the
    /// cursor in the field.
    func newViewState(for item: ItemID, fresh: Bool) -> FocusRequestState {
        FocusRequestState(focusPending: fresh)
    }

    func content(of item: ItemID, viewState: FocusRequestState) -> some View {
        if let microapp = microapps[item] {
            MakerView(app: self, item: item, microapp: microapp, state: viewState)
        }
    }

    /// Text typed before the description field took the focus goes into it.
    func typeAhead(_ text: String, into item: ItemID, viewState: FocusRequestState) {
        guard let microapp = microapps[item], case .describing = microapp.status else { return }
        microapp.draft += text
    }

    // MARK: What the views ask for

    func make(_ item: ItemID) {
        microapps[item]?.make(services.claude)
    }

    func change(_ item: ItemID) {
        microapps[item]?.change(services.claude)
    }

    func fix(_ item: ItemID) {
        microapps[item]?.fix(services.claude)
    }

    func revert(_ item: ItemID) {
        microapps[item]?.revert()
    }

    /// Notes that a microapp's page loaded; a new one rises.
    func loaded(_ item: ItemID) {
        if microapps[item]?.loaded(at: now()) == true {
            risen.insert(item)
        }
    }

    func report(_ problem: String, in item: ItemID) {
        microapps[item]?.report(problem, at: now())
    }

    func resize(_ item: ItemID, to size: CGSize) {
        microapps[item]?.resize(to: size)
    }

    // MARK: Keeping microapps

    /// Forgets a microapp, stopping Claude, and moves its folder to the Trash.
    func remove(_ item: ItemID) {
        guard let microapp = microapps[item] else { return }
        microapp.cancel()
        microapp.folder.trash()
        microapps.remove(item)
        risen.remove(item)
    }

    var items: [ItemID] { microapps.items }

    /// A microapp as saved between launches. Its page is in its folder, and
    /// what the page says about itself is read from there.
    private struct SavedMicroapp: Codable {
        var id: ItemID
        var folder: String
        var description: String?
        var draft: String
        var width: CGFloat?
        var height: CGFloat?
        /// Why Claude stopped, if it did.
        var error: String?
    }

    func save() -> Data? {
        microapps.save { id, microapp in
            SavedMicroapp(
                id: id, folder: microapp.folder.name, description: microapp.description,
                draft: microapp.draft, width: microapp.size?.width,
                height: microapp.size?.height, error: microapp.savedError)
        }
    }

    /// Takes back the saved microapps, and moves to the Trash the folders
    /// of microapps no longer kept, such as one deleted while Honu was not
    /// running to see it.
    func load(_ data: Data) {
        guard (try? JSONDecoder().decode([SavedMicroapp].self, from: data)) != nil else { return }
        microapps.load(data, as: SavedMicroapp.self) { saved in
            let size = saved.width.flatMap { width in
                saved.height.map { CGSize(width: width, height: $0) }
            }
            return (
                saved.id,
                GeneratedApp(
                    folder: folder(named: saved.folder), description: saved.description,
                    draft: saved.draft, size: size, error: saved.error)
            )
        }
        let kept = Set(microapps.byID.values.map(\.folder.name))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path())) ?? []
        for name in names where !kept.contains(name) && UUID(uuidString: name) != nil {
            folder(named: name).trash()
        }
    }
}

extension CGSize {
    fileprivate static func + (a: CGSize, b: CGSize) -> CGSize {
        CGSize(width: a.width + b.width, height: a.height + b.height)
    }
}
