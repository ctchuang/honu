import Foundation
import Testing

@testable import Honu

/// Running a microapp's page, apart from where the page comes from.
@MainActor
struct PageTests {
    @Test func aSchemeServesUnderItsOwnName() {
        let folder = URL(filePath: "/tmp/pages/clock", directoryHint: .isDirectory)
        let site = MicroappScheme(folder: folder, scheme: "honu-test")
        #expect(site.scheme == "honu-test")
        #expect(site.pageURL.absoluteString == "honu-test://clock/index.html")
        #expect(site.file(at: site.pageURL)?.path() == "/tmp/pages/clock/index.html")
        #expect(
            site.file(at: URL(string: "honu-test://clock/app.js")!)?.path()
                == "/tmp/pages/clock/app.js")
        #expect(site.file(at: URL(string: "honu-test://clock/../other/index.html")!) == nil)
        #expect(site.file(at: URL(string: "honu-test://clock/instances/A.json")!) == nil)
    }

    @Test func theMicroappsSchemeIsTheDefault() {
        let folder = URL(filePath: "/tmp/microapps/A1", directoryHint: .isDirectory)
        let site = MicroappScheme(folder: folder)
        #expect(site.scheme == MicroappScheme.scheme)
        #expect(site.pageURL == MicroappScheme.url(of: folder))
    }

    @Test func theMakerHearsFromItsPages() throws {
        let claude = FakeClaude()
        let shell = makeShell(claude: claude)
        let (bubble, _) = try shell.makeMicroapp("Clock", claude: claude)
        let host: any PageHost = shell.maker
        host.resize(bubble.target.item, to: CGSize(width: 500, height: 300))
        shell.tick(at: 2)
        #expect(bubble.size == CGSize(width: 500, height: 300) + MakerApp.chrome)
    }
}
