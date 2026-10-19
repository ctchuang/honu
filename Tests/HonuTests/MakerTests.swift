import Foundation
import Testing

@testable import Honu

@MainActor
struct MakerTests {
    @Test func microappsAreKeptBesideTheStore() {
        #expect(
            MakerApp.root(for: Autosave.defaultURL)
                == Services.folder.appending(path: "microapps", directoryHint: .isDirectory))
        #expect(
            MakerApp.root(for: URL(filePath: "/tmp/honu.json")).path() == "/tmp/honu.microapps")
    }

    @Test func theSchemeServesOnlyTheMicroappsOwnFolder() {
        let folder = URL(filePath: "/tmp/microapps/A1", directoryHint: .isDirectory)
        let scheme = MicroappScheme(folder: folder)
        #expect(MicroappScheme.url(of: folder).absoluteString == "honu-app://A1/index.html")
        #expect(
            scheme.file(at: URL(string: "honu-app://A1/")!)?.path()
                == "/tmp/microapps/A1/index.html")
        #expect(
            scheme.file(at: URL(string: "honu-app://A1/img/a.png")!)?.path()
                == "/tmp/microapps/A1/img/a.png")
        #expect(scheme.file(at: URL(string: "honu-app://A1/../B2/data.json")!) == nil)
        #expect(scheme.file(at: URL(string: "honu-app://A1/%2E%2E/B2/data.json")!) == nil)
        #expect(
            scheme.file(at: URL(string: "honu-app://A1/a%20b.png")!)?.path(percentEncoded: false)
                == "/tmp/microapps/A1/a b.png")
    }

    @Test func aMicroappsFolderGoesWithIt() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let maker = MakerApp(root: root)
        let item = maker.create()
        let folder = try #require(maker.folder(of: item))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "index.html").path()))

        let restored = MakerApp(root: root)
        restored.load(try #require(maker.save()))
        #expect(restored.folder(of: item) == folder)

        maker.remove(item)
        #expect(!FileManager.default.fileExists(atPath: folder.path()))
    }
}
