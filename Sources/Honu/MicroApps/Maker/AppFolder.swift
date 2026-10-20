import Foundation

/// A microapp's folder: its page (`index.html`), what it saves
/// (`data.json`, written by `Bridge`), and the pages it had before each
/// change (`history/1.html`, `2.html`, …), so a change can be undone.
struct AppFolder: Equatable {
    let url: URL

    var name: String { url.lastPathComponent }
    var pageURL: URL { url.appending(path: "index.html") }
    var historyURL: URL { url.appending(path: "history", directoryHint: .isDirectory) }

    /// The page, if one has been written.
    func page() -> String? {
        try? String(contentsOf: pageURL, encoding: .utf8)
    }

    /// Writes `page`, keeping the page it replaces in the history.
    func write(_ page: String) throws {
        let files = FileManager.default
        try files.createDirectory(at: url, withIntermediateDirectories: true)
        if files.fileExists(atPath: pageURL.path()) {
            try files.createDirectory(at: historyURL, withIntermediateDirectories: true)
            try files.moveItem(at: pageURL, to: historyFile(versions.count + 1))
        }
        try Data(page.utf8).write(to: pageURL, options: .atomic)
    }

    /// The numbers of the pages kept in the history, oldest first.
    var versions: [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: historyURL.path())) ?? []
        return names.compactMap { name in
            name.hasSuffix(".html") ? Int(name.dropLast(5)) : nil
        }.sorted()
    }

    /// Puts back the page before the last change. Returns whether there was one.
    func revert() throws -> Bool {
        guard let last = versions.last else { return false }
        let files = FileManager.default
        try? files.removeItem(at: pageURL)
        try files.moveItem(at: historyFile(last), to: pageURL)
        return true
    }

    /// Moves the folder to the Trash.
    func trash() {
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private func historyFile(_ version: Int) -> URL {
        historyURL.appending(path: "\(version).html")
    }
}
