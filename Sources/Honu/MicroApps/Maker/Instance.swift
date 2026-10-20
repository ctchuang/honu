import Foundation
import Observation

/// One launch of a microapp, the item a bubble shows: the microapp it runs,
/// and what is its own, its saved state and the size its page asked for.
/// Every instance of a microapp runs the same page.
@Observable
@MainActor
final class Instance {
    let app: GeneratedApp
    /// Names the file in the microapp's folder that its page's state is
    /// saved in. A UUID rather than the item id, which restarts with a new store.
    let dataID: UUID
    /// The size the page asked for with `honu.resize`, and the version of
    /// the page that asked: a new page starts at the size it declares.
    private var resized: (size: CGSize, version: Int)?

    /// An instance of `app` saving to the file `dataID` names, at `size` if
    /// its page asked for one.
    init(app: GeneratedApp, dataID: UUID = UUID(), size: CGSize? = nil) {
        self.app = app
        self.dataID = dataID
        if let size {
            resize(to: size)
        }
    }

    /// Where its page's state is saved.
    var dataURL: URL { app.folder.dataURL(for: dataID) }

    /// The size of its page: the one it asked for last, or else the one the
    /// page declares.
    var size: CGSize? {
        if let resized, resized.version == app.version {
            return resized.size
        }
        return app.meta.size
    }

    /// Takes the size the page asked for, within limits.
    func resize(to size: CGSize) {
        resized = (AppSource.clamped(size), app.version)
    }

    /// Deletes its saved state, as when it is deleted.
    func deleteData() {
        try? FileManager.default.removeItem(at: dataURL)
    }
}
