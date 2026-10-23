import Foundation

/// A microapp built into Honu as a web page: its folder in Honu's resources,
/// named by its id, and what its page says about itself.
struct BundledPage: Equatable {
    /// Its id, the name of its folder, which names its data and its saved
    /// items, and is the host of its page's URL.
    let name: String
    let folder: URL
    let meta: PageMeta

    /// What it is called: its page's title, or else its name.
    var label: String { shortLabel(meta.title ?? name) }
}

/// The microapps built into Honu as web pages: the folders of `BuiltinApps/`
/// in its resources, each holding an `index.html`.
enum BuiltinCatalog {
    /// The scheme their pages are served by, apart from the microapps
    /// Claude makes, so the two never share an origin.
    static let scheme = "honu-builtin"

    /// Where they are in Honu's resources, if any are.
    static var resourcesURL: URL? {
        Bundle.module.url(forResource: "BuiltinApps", withExtension: nil)
    }

    /// The ones shipped with Honu.
    static var shipped: [BundledPage] {
        resourcesURL.map(pages(in:)) ?? []
    }

    /// Whether `name` can name one: lowercase letters, digits, and hyphens,
    /// starting with a letter. It is the host of its page's URL, which
    /// ignores case, so names differing only in case would share an origin
    /// and a data folder.
    static func isValidName(_ name: String) -> Bool {
        name.wholeMatch(of: /[a-z][a-z0-9-]*/) != nil
    }

    /// The pages in the folders of `root` whose names are valid and that
    /// hold an `index.html`, by label and then by name.
    static func pages(in root: URL) -> [BundledPage] {
        let files = FileManager.default
        let names = (try? files.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        return names.filter(isValidName).compactMap { name -> BundledPage? in
            let folder = root.appending(path: name, directoryHint: .isDirectory)
            guard
                let page = try? String(
                    contentsOf: folder.appending(path: "index.html"), encoding: .utf8)
            else { return nil }
            return BundledPage(name: name, folder: folder, meta: AppSource.meta(of: page))
        }.sorted {
            switch $0.label.localizedStandardCompare($1.label) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.name < $1.name
            }
        }
    }
}
