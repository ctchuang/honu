import Foundation
import Testing

@testable import Honu

@MainActor
struct StageTests {
    private let target = ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1))

    private func stage() -> Stage {
        Stage(size: CGSize(width: 1200, height: 800))
    }

    @discardableResult
    private func add(_ stage: Stage, x: CGFloat) -> Bubble {
        stage.add(
            target: target, center: CGPoint(x: x, y: 300), appearance: Appearance(), viewState: nil)
    }

    @Test func draggedBubbleStaysOnTop() {
        let stage = stage()
        let first = add(stage, x: 100)
        let second = add(stage, x: 400)
        #expect(first.id != second.id)
        let picked = stage.bubble(at: CGPoint(x: 100, y: 300))
        #expect(picked === first)
        stage.startDrag(first)
        #expect(stage.bubbles.last === first)
        add(stage, x: 700)
        #expect(stage.bubbles.last === first, "new bubble went on top")

        stage.dragged(by: CGSize(width: 50, height: 0), doomed: false)
        #expect(stage.dragDistance == 50)
        let dropped = stage.endDrag()
        #expect(dropped?.bubble === first && dropped?.home == CGPoint(x: 100, y: 300))
        #expect(!stage.isDragging)
        #expect(stage.bubbles.count == 3)
    }

    @Test func swallowedBubbleStaysOutOfReachUntilSpatBackOrRemoved() {
        let stage = stage()
        let below = add(stage, x: 100)
        let eaten = add(stage, x: 400)
        let mouth = CGPoint(x: 1100, y: 750)
        stage.swallow(eaten, into: mouth)
        #expect(stage.shows(target))
        #expect(stage.bubble(at: mouth) == nil, "swallowed bubble can be grabbed")
        #expect(stage.bubble(at: CGPoint(x: 400, y: 300)) == nil)
        #expect(stage.bubble(at: CGPoint(x: 100, y: 300)) === below)

        let home = CGPoint(x: 400, y: 300)
        add(stage, x: 700)
        stage.spitBack(eaten, from: mouth, to: home)
        #expect(stage.bubbles.last === eaten)
        #expect(!eaten.isSwallowed && eaten.destination == home)

        #expect(stage.remove(eaten.id) === eaten)
        #expect(stage.remove(eaten.id) == nil)
        #expect(stage.bubbles.count == 2)
    }

    @Test func newBubblesStepAsideFromEachOther() {
        let stage = stage()
        let mouth = CGPoint(x: 100, y: 700)
        let a = add(stage, x: 0)
        stage.spit(a, from: mouth)
        let b = add(stage, x: 0)
        stage.spit(b, from: mouth)
        #expect(b.destination.x - a.destination.x == Stage.cascadeStep)
        #expect(b.destination.y - a.destination.y == Stage.cascadeStep)
        // They fly from the mouth and cannot be grabbed until they land.
        #expect(a.center == mouth && a.isInFlight)
    }

    @Test func newBubblesLandOnScreen() {
        let stage = stage()
        let bubble = add(stage, x: 0)
        stage.spit(bubble, from: CGPoint(x: stage.size.width - 10, y: 20))
        let landing = CGRect(
            x: bubble.destination.x - bubble.size.width / 2,
            y: bubble.destination.y - bubble.size.height / 2,
            width: bubble.size.width, height: bubble.size.height)
        #expect(CGRect(origin: .zero, size: stage.size).contains(landing))
    }
}

@MainActor
struct BubbleShapeTests {
    private func bubble() -> Bubble {
        Bubble(
            id: BubbleID(rawValue: 1),
            target: ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1)),
            center: CGPoint(x: 500, y: 300),
            appearance: Appearance(size: CGSize(width: 100, height: 100)), viewState: nil)
    }

    @Test func roundedCornersAreNotHit() {
        let bubble = bubble()
        #expect(bubble.contains(CGPoint(x: 500, y: 300)), "middle")
        #expect(bubble.contains(CGPoint(x: 451, y: 300)), "left edge")
        #expect(bubble.contains(CGPoint(x: 500, y: 349)), "bottom edge")
        #expect(!bubble.contains(CGPoint(x: 451, y: 251)), "top-left corner")
        #expect(!bubble.contains(CGPoint(x: 549, y: 349)), "bottom-right corner")
        #expect(!bubble.contains(CGPoint(x: 560, y: 300)), "outside")
        #expect(bubble.contains(CGPoint(x: 465, y: 265)), "inside the corner's curve")
    }

    @Test func aShrunkBubbleIsHitOnlyWhereItIsDrawn() {
        let doomed = bubble()
        doomed.isDoomed = true
        #expect(doomed.contains(CGPoint(x: 500, y: 300)))
        #expect(!doomed.contains(CGPoint(x: 545, y: 300)), "hit past its shrunk edge")
    }

    @Test func clicksPastACornerReachTheBubbleBelow() {
        let stage = Stage(size: CGSize(width: 1200, height: 800))
        let target = ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1))
        let below = stage.add(
            target: target, center: CGPoint(x: 440, y: 240),
            appearance: Appearance(size: CGSize(width: 100, height: 100)), viewState: nil)
        let above = stage.add(
            target: target, center: CGPoint(x: 500, y: 300),
            appearance: Appearance(size: CGSize(width: 100, height: 100)), viewState: nil)
        #expect(stage.bubble(at: CGPoint(x: 500, y: 300)) === above)
        // Past the top bubble's rounded corner, inside the one below it.
        #expect(stage.bubble(at: CGPoint(x: 452, y: 252)) === below)
    }
}
