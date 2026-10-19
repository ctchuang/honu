import SwiftUI

/// The Maker microapp, for now a prototype: each item is a microapp, a
/// folder holding a web page that runs in its bubble. Until Claude writes
/// them, every new one gets the hand-written probe page, which checks what
/// a microapp can do and how the keyboard reaches it.
@Observable
@MainActor
final class MakerApp: MicroApp {
    let id = AppID("maker")
    let menuLabel = "Microapp Probe"

    /// Where the microapps' folders are.
    let root: URL
    /// The model: each microapp's folder name.
    private(set) var microapps = ItemTable<String>()

    init(root: URL) {
        self.root = root
    }

    /// Where the microapps of the store at `storeURL` are kept: `microapps/`
    /// beside Honu's own store, or `<name>.microapps/` beside another.
    static func root(for storeURL: URL) -> URL {
        if storeURL == Autosave.defaultURL {
            return Services.folder.appending(path: "microapps", directoryHint: .isDirectory)
        }
        return storeURL.deletingPathExtension().appendingPathExtension("microapps")
    }

    func create() -> ItemID {
        let name = UUID().uuidString
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(ProbePage.html.utf8).write(to: folder.appending(path: "index.html"))
        return microapps.insert(name)
    }

    func appearance(of item: ItemID) -> Appearance {
        Appearance(symbol: "hammer.fill", panelSize: CGSize(width: 440, height: 560))
    }

    func title(of item: ItemID) -> String {
        "Probe"
    }

    func content(of item: ItemID, viewState: NoViewState) -> some View {
        MicroappView(folder: folder(of: item) ?? root)
    }

    /// The microapp's folder.
    func folder(of item: ItemID) -> URL? {
        microapps[item].map { root.appending(path: $0, directoryHint: .isDirectory) }
    }

    func remove(_ item: ItemID) {
        if let folder = folder(of: item) {
            try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        }
        microapps.remove(item)
    }

    var items: [ItemID] { microapps.items }

    private struct SavedMicroapp: Codable {
        var id: ItemID
        var folder: String
    }

    func save() -> Data? {
        microapps.save { SavedMicroapp(id: $0, folder: $1) }
    }

    func load(_ data: Data) {
        microapps.load(data, as: SavedMicroapp.self) { ($0.id, $0.folder) }
    }
}
