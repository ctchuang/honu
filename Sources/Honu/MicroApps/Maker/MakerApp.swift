import AppKit
import SwiftUI

/// The Maker microapp: any number of microapps Claude writes, each running
/// in any number of instances, the items its bubbles show. In a new one's
/// bubble you describe what you want; Claude writes a web page that does it,
/// which then runs in the bubble, and which you can ask Claude to change.
/// Once its first page is written, a microapp is installed: it stays,
/// whether or not any instance of it does, and can be launched again. Each
/// microapp keeps its page, and what each instance saves, in a folder of its
/// own.
@Observable
@MainActor
final class MakerApp: MicroApp {
    let id = AppID("maker")
    let launcherLabel = "New Microapp"
    let launcherSymbol = "plus"

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
    /// Every microapp, oldest first: those installed, and those still being
    /// described or made.
    private(set) var apps: [GeneratedApp] = []
    /// The model: each instance, by the item it is.
    private(set) var instances = ItemTable<Instance>()
    @ObservationIgnored let services: Services
    /// Instances whose new page has loaded since the last `update`, whose
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

    /// The installed microapps, the ones whose first page has been written,
    /// in the order they were made.
    var library: [GeneratedApp] { apps.filter(\.hasPage) }

    /// The microapp `item` runs.
    func microapp(of item: ItemID) -> GeneratedApp? {
        instances[item]?.app
    }

    /// The instances of `microapp`, oldest first.
    func items(of microapp: GeneratedApp) -> [ItemID] {
        instances.entries.filter { $0.value.app === microapp }.map(\.id)
    }

    /// Starts a microapp with nothing described yet, in one instance. Its
    /// folder is made when its first page is written.
    func create() -> ItemID {
        let microapp = GeneratedApp(folder: folder(named: UUID().uuidString))
        apps.append(microapp)
        return instances.insert(Instance(app: microapp))
    }

    /// Starts a new instance of the installed microapp whose folder is
    /// named `name`, its page running at once.
    func launch(_ name: String) -> ItemID? {
        guard let microapp = library.first(where: { $0.folder.name == name }) else { return nil }
        return instances.insert(Instance(app: microapp))
    }

    func appearance(of item: ItemID) -> Appearance {
        guard let instance = instances[item] else { return Appearance() }
        let microapp = instance.app
        let panel: CGSize =
            switch microapp.status {
            case .describing: Self.describingSize
            case .writing(.making): Self.writingSize
            case .writing, .running:
                (instance.size ?? Self.defaultPageSize) + Self.chrome
            }
        return Appearance(symbol: Self.symbol(of: microapp), panelSize: panel)
    }

    /// The SF Symbol of `microapp`: the one its page names, if it exists.
    static func symbol(of microapp: GeneratedApp) -> String {
        let named = microapp.meta.symbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0
        }
        return named ?? defaultSymbol
    }

    func title(of item: ItemID) -> String {
        guard let microapp = microapp(of: item) else { return Self.emptyLabel }
        return Self.name(of: microapp)
    }

    /// What `microapp` is called: its page's title, or else its description.
    static func name(of microapp: GeneratedApp) -> String {
        shortLabel(microapp.meta.title ?? microapp.description ?? emptyLabel)
    }

    /// Whether Claude is writing a microapp's page.
    func isBusy(_ item: ItemID) -> Bool {
        microapp(of: item)?.isBusy ?? false
    }

    /// Takes in what Claude has written, and fixes pages' errors when due.
    /// The bubbles of every instance of a microapp wobble when writing it
    /// fails, and rise when its new page has loaded.
    func update(_ context: Context) {
        let time = now()
        for microapp in apps where microapp.poll(services.claude, at: time) == .needsAttention {
            for item in items(of: microapp) {
                context.play(.wobble, for: item)
            }
        }
        for item in risen.sorted() {
            context.play(.rise, for: item)
        }
        risen.removeAll()
    }

    /// A new microapp is to be described, so its bubble starts with the
    /// cursor in the field; a new instance of one already made has no field
    /// to take what is typed.
    func newViewState(for item: ItemID, fresh: Bool) -> FocusRequestState {
        var describing = false
        if case .describing = microapp(of: item)?.status {
            describing = true
        }
        return FocusRequestState(focusPending: fresh && describing)
    }

    func content(of item: ItemID, viewState: FocusRequestState) -> some View {
        if let instance = instances[item] {
            MakerView(app: self, item: item, instance: instance, state: viewState)
        }
    }

    /// Text typed before the description field took the focus goes into it.
    func typeAhead(_ text: String, into item: ItemID, viewState: FocusRequestState) {
        guard let microapp = microapp(of: item), case .describing = microapp.status else { return }
        microapp.draft += text
    }

    // MARK: What the views ask for

    func make(_ item: ItemID) {
        microapp(of: item)?.make(services.claude)
    }

    func change(_ item: ItemID) {
        microapp(of: item)?.change(services.claude)
    }

    func fix(_ item: ItemID) {
        microapp(of: item)?.fix(services.claude)
    }

    func revert(_ item: ItemID) {
        microapp(of: item)?.revert()
    }

    /// Notes that an instance's page loaded; a new page rises in every
    /// instance of its microapp.
    func loaded(_ item: ItemID) {
        guard let microapp = microapp(of: item) else { return }
        if microapp.loaded(at: now()) {
            risen.formUnion(items(of: microapp))
        }
    }

    func report(_ problem: String, in item: ItemID) {
        microapp(of: item)?.report(problem, at: now())
    }

    func resize(_ item: ItemID, to size: CGSize) {
        instances[item]?.resize(to: size)
    }

    // MARK: Keeping microapps

    /// Forgets an instance and deletes what it saved. A microapp never
    /// installed goes with its last instance: Claude stops, and its folder
    /// goes to the Trash.
    func remove(_ item: ItemID) {
        guard let instance = instances[item] else { return }
        instances.remove(item)
        risen.remove(item)
        instance.deleteData()
        let microapp = instance.app
        if !microapp.hasPage, items(of: microapp).isEmpty {
            microapp.cancel()
            microapp.folder.trash()
            apps.removeAll { $0 === microapp }
        }
    }

    var items: [ItemID] { instances.items }

    /// What is saved between launches: each microapp, and each instance.
    private struct Saved: Codable {
        var apps: [SavedMicroapp]
        var instances: [SavedInstance]
    }

    /// A microapp as saved between launches. Its page is in its folder, and
    /// what the page says about itself is read from there.
    private struct SavedMicroapp: Codable {
        var folder: String
        var description: String?
        var draft: String
        /// Why Claude stopped, if it did.
        var error: String?
    }

    /// An instance as saved between launches, naming its microapp by folder.
    private struct SavedInstance: Codable {
        var id: ItemID
        var folder: String
        var data: UUID
        var width: CGFloat?
        var height: CGFloat?
    }

    func save() -> Data? {
        let saved = Saved(
            apps: apps.map {
                SavedMicroapp(
                    folder: $0.folder.name, description: $0.description, draft: $0.draft,
                    error: $0.savedError)
            },
            instances: instances.entries.map { id, instance in
                SavedInstance(
                    id: id, folder: instance.app.folder.name, data: instance.dataID,
                    width: instance.size?.width, height: instance.size?.height)
            })
        return try? JSONEncoder().encode(saved)
    }

    /// A microapp as saved before a microapp could run more than once: the
    /// one instance it had, and what the page saved in its folder.
    private struct OldSavedMicroapp: Codable {
        var id: ItemID
        var folder: String
        var description: String?
        var draft: String
        var width: CGFloat?
        var height: CGFloat?
        var error: String?
    }

    /// Takes in microapps saved before a microapp could run more than once:
    /// each becomes a microapp with one instance, and what its page saved
    /// moves to that instance's file.
    private func upgrade(_ data: Data) -> Saved? {
        guard let old = try? JSONDecoder().decode([OldSavedMicroapp].self, from: data) else {
            return nil
        }
        var saved = Saved(apps: [], instances: [])
        for microapp in old {
            let instance = SavedInstance(
                id: microapp.id, folder: microapp.folder, data: UUID(), width: microapp.width,
                height: microapp.height)
            saved.apps.append(
                SavedMicroapp(
                    folder: microapp.folder, description: microapp.description,
                    draft: microapp.draft, error: microapp.error))
            saved.instances.append(instance)
            let folder = folder(named: microapp.folder)
            let files = FileManager.default
            guard files.fileExists(atPath: folder.oldDataURL.path()) else { continue }
            try? files.createDirectory(at: folder.instancesURL, withIntermediateDirectories: true)
            try? files.moveItem(at: folder.oldDataURL, to: folder.dataURL(for: instance.data))
        }
        return saved
    }

    /// Takes back the saved microapps and instances. A microapp not
    /// installed that no instance runs is forgotten, and folders no
    /// microapp has, such as one deleted while Honu was not running to see
    /// it, go to the Trash, as do the files of instances no longer kept.
    func load(_ data: Data) {
        guard let saved = (try? JSONDecoder().decode(Saved.self, from: data)) ?? upgrade(data)
        else { return }
        var byFolder: [String: GeneratedApp] = [:]
        for microapp in saved.apps where byFolder[microapp.folder] == nil {
            byFolder[microapp.folder] = GeneratedApp(
                folder: folder(named: microapp.folder), description: microapp.description,
                draft: microapp.draft, error: microapp.error)
        }
        for instance in saved.instances {
            guard let microapp = byFolder[instance.folder] else { continue }
            let size = instance.width.flatMap { width in
                instance.height.map { CGSize(width: width, height: $0) }
            }
            instances.restore(
                instance.id, Instance(app: microapp, dataID: instance.data, size: size))
        }
        let running = Set(instances.entries.map { ObjectIdentifier($0.value.app) })
        apps = saved.apps.compactMap { byFolder.removeValue(forKey: $0.folder) }.filter {
            $0.hasPage || running.contains(ObjectIdentifier($0))
        }
        let kept = Set(apps.map(\.folder.name))
        let files = FileManager.default
        let names = (try? files.contentsOfDirectory(atPath: root.path())) ?? []
        for name in names where !kept.contains(name) && UUID(uuidString: name) != nil {
            folder(named: name).trash()
        }
        let saving = Set(instances.entries.map { $0.value.dataURL.standardizedFileURL })
        for microapp in apps {
            let folder = microapp.folder.instancesURL
            for name in (try? files.contentsOfDirectory(atPath: folder.path())) ?? [] {
                let file = folder.appending(path: name).standardizedFileURL
                if !saving.contains(file) {
                    try? files.removeItem(at: file)
                }
            }
        }
    }
}
