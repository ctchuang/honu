import SwiftUI

/// A microapp built into Honu as a web page (`BundledPage`), running as the
/// microapps Claude makes do, but never changed: any number of instances,
/// each with its own saved state, kept in a folder of its own apart from
/// the page, which is read-only. Its bubbles rise once the page loads, and
/// wobble when it reports an error.
@Observable
@MainActor
final class BundledWebApp: MicroApp, PageHost {
    let page: BundledPage
    /// Where what its instances save is kept.
    let dataFolder: URL

    /// The bubble's size not taken by the page: the title bar and margins.
    static let chrome = CGSize(width: 20, height: 46)
    /// The prefix of their ids, apart from the other microapps'.
    static let idPrefix = "builtin."

    /// One instance: the file its page's state is saved in, named by a
    /// UUID, and the size its page asked for, if it did.
    struct Instance: Equatable {
        var dataID = UUID()
        var size: CGSize?
    }

    /// The model: each instance, by the item it is.
    private(set) var instances = ItemTable<Instance>()
    /// Instances whose page loaded since the last `update`, whose bubbles rise.
    @ObservationIgnored private var risen: Set<ItemID> = []
    /// Instances whose page reported an error since the last `update`,
    /// whose bubbles wobble.
    @ObservationIgnored private var troubled: Set<ItemID> = []
    /// Instances whose page has reported an error since it loaded, which
    /// do not wobble again until it loads again.
    @ObservationIgnored private var reported: Set<ItemID> = []

    /// `page`, saving what its instances do under `root`.
    init(page: BundledPage, root: URL) {
        self.page = page
        dataFolder = root.appending(path: page.name, directoryHint: .isDirectory)
    }

    /// Where the data of the microapps built in as web pages is kept, for
    /// the store at `storeURL`: `builtin/` beside Honu's own store, or
    /// `<name>.builtin/` beside another.
    static func root(for storeURL: URL) -> URL {
        if storeURL == Autosave.defaultURL {
            return Services.folder.appending(path: "builtin", directoryHint: .isDirectory)
        }
        return storeURL.deletingPathExtension().appendingPathExtension("builtin")
    }

    var id: AppID { AppID(Self.idPrefix + page.name) }
    var launcherLabel: String { page.label }
    var launcherSymbol: String { MakerApp.symbol(named: page.meta.symbol) }

    /// Where the instances' files are.
    var instancesURL: URL {
        dataFolder.appending(path: AppFolder.instances, directoryHint: .isDirectory)
    }

    /// Where the instance `item` saves its page's state.
    func dataURL(of item: ItemID) -> URL? {
        instances[item].map { instancesURL.appending(path: "\($0.dataID.uuidString).json") }
    }

    /// How its page is served.
    var site: MicroappScheme {
        MicroappScheme(folder: page.folder, scheme: BuiltinCatalog.scheme)
    }

    func create() -> ItemID {
        instances.insert(Instance())
    }

    /// The size its page asked for last, or else the one it declares; a
    /// page is never smaller than pages may ask to be.
    func appearance(of item: ItemID) -> Appearance {
        let size = instances[item]?.size ?? page.meta.size ?? MakerApp.defaultPageSize
        return Appearance(size: size + Self.chrome, minSize: AppSource.minSize + Self.chrome)
    }

    func title(of item: ItemID) -> String {
        launcherLabel
    }

    func content(of item: ItemID, viewState: NoViewState) -> some View {
        if let dataURL = dataURL(of: item) {
            MicroappView(host: self, item: item, site: site, dataURL: dataURL, version: 0)
        }
    }

    func update(_ context: Context) {
        for item in risen.sorted() {
            context.play(.rise, for: item)
        }
        for item in troubled.sorted() {
            context.play(.wobble, for: item)
        }
        risen.removeAll()
        troubled.removeAll()
    }

    // MARK: What its pages do

    func loaded(_ item: ItemID, at time: TimeInterval = now()) {
        guard instances[item] != nil else { return }
        risen.insert(item)
        reported.remove(item)
    }

    /// A page's error wobbles its bubbles, once until the page loads again,
    /// so a page that keeps failing does not keep them shaking.
    func report(_ problem: String, in item: ItemID, at time: TimeInterval = now()) {
        guard instances[item] != nil, !reported.contains(item) else { return }
        reported.insert(item)
        troubled.insert(item)
    }

    func resize(_ item: ItemID, to size: CGSize) {
        guard var instance = instances[item] else { return }
        instance.size = AppSource.clamped(size)
        instances.update(item, to: instance)
    }

    // MARK: Keeping instances

    /// Forgets an instance and deletes what it saved.
    func remove(_ item: ItemID) {
        let file = dataURL(of: item)
        instances.remove(item)
        risen.remove(item)
        troubled.remove(item)
        reported.remove(item)
        if let file {
            try? FileManager.default.removeItem(at: file)
        }
    }

    var items: [ItemID] { instances.items }

    private struct SavedInstance: Codable {
        var id: ItemID
        var data: UUID
        var width: CGFloat?
        var height: CGFloat?
    }

    func save() -> Data? {
        instances.save {
            SavedInstance(id: $0, data: $1.dataID, width: $1.size?.width, height: $1.size?.height)
        }
    }

    /// Takes back the saved instances, and deletes the files of instances
    /// no longer kept.
    func load(_ data: Data) {
        instances.load(data, as: SavedInstance.self) { saved in
            let size = saved.width.flatMap { width in
                saved.height.map { CGSize(width: width, height: $0) }
            }
            return (saved.id, Instance(dataID: saved.data, size: size))
        }
        deleteUnkeptFiles()
    }

    private func deleteUnkeptFiles() {
        let files = FileManager.default
        let kept = Set(instances.entries.map { "\($0.value.dataID.uuidString).json" })
        let names = (try? files.contentsOfDirectory(atPath: instancesURL.path())) ?? []
        for name in names where !kept.contains(name) {
            try? files.removeItem(at: instancesURL.appending(path: name))
        }
    }
}
