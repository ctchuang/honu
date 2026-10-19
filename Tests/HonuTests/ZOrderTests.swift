import Foundation
import Testing

@testable import Honu

@MainActor
struct ZOrderTests {
    private let stage = Stage(size: CGSize(width: 1200, height: 800))
    private let target = ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1))

    @discardableResult
    private func add(_ x: CGFloat, _ y: CGFloat) -> Bubble {
        stage.add(
            target: target, center: CGPoint(x: x, y: y), appearance: Appearance(closedSide: 100),
            viewState: nil)
    }

    @Test func aBubbleIsCutAwayWhereABubbleAboveLies() throws {
        add(500, 300)
        add(560, 330)
        let cuts = StageView.cuts(of: 0, in: stage.bubbles)
        let cut = try #require(cuts.first)
        #expect(cuts.count == 1)
        // In the lower bubble's own coordinates (its top-left corner is at
        // 450, 250), grown by the gap.
        let gap = StageView.gap
        #expect(
            cut.rect
                == CGRect(x: 60 - gap, y: 30 - gap, width: 100 + 2 * gap, height: 100 + 2 * gap))
        #expect(abs(cut.cornerRadius - (28 + gap)) < 0.001)
        // Nothing lies above the top one.
        #expect(StageView.cuts(of: 1, in: stage.bubbles).isEmpty)
    }

    @Test func onlyOverlappingVisibleBubblesCut() {
        add(500, 300)
        add(900, 300)
        let swallowed = add(520, 300)
        stage.swallow(swallowed, into: CGPoint(x: 1100, y: 750))
        for frame in 0..<60 {
            stage.step(time: Double(frame) / 60, dt: 1.0 / 60)
        }
        #expect(StageView.cuts(of: 0, in: stage.bubbles).isEmpty)
    }

    @Test func cutsFollowAShrunkBubble() throws {
        let below = add(500, 300)
        below.isDoomed = true
        add(560, 300)
        let cut = try #require(StageView.cuts(of: 0, in: stage.bubbles).first)
        // Shrunk to 0.6 around its center at 500, it is drawn from 470 to 530,
        // so the cover's edge at 510 lies 10 points past its center, which is
        // 10 / 0.6 in its own coordinates, where its center is at 50.
        let scale = Bubble.doomedScale
        #expect(abs(cut.rect.minX - (50 + (10 - StageView.gap) / scale)) < 0.001)
        #expect(abs(cut.rect.width - (100 + 2 * StageView.gap) / Bubble.doomedScale) < 0.001)
    }

    @Test func pressingABubbleBringsItToTheTop() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "honu-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "state.json")
        let shell = Shell(
            size: CGSize(width: 1200, height: 800), storeURL: url,
            services: Services(claude: FakeClaude()))
        let target = ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1))
        let below = shell.stage.add(
            target: target, center: CGPoint(x: 500, y: 300),
            appearance: Appearance(closedSide: 100), viewState: nil)
        shell.stage.add(
            target: target, center: CGPoint(x: 560, y: 330),
            appearance: Appearance(closedSide: 100), viewState: nil)
        shell.press(at: CGPoint(x: 470, y: 290))
        #expect(shell.stage.bubbles.last === below)
        #expect(StageView.cuts(of: 1, in: shell.stage.bubbles).isEmpty)
        #expect(StageView.cuts(of: 0, in: shell.stage.bubbles).count == 1)
    }
}
