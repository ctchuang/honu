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

    @Test func newPanelsStepAsideFromEachOther() {
        let stage = stage()
        let mouth = CGPoint(x: 100, y: 700)
        let a = add(stage, x: 0)
        stage.spitPanel(a, from: mouth)
        let b = add(stage, x: 0)
        stage.spitPanel(b, from: mouth)
        #expect(b.destination.x - a.destination.x == Stage.cascadeStep)
        #expect(b.destination.y - a.destination.y == Stage.cascadeStep)
        // They fly from the mouth and cannot be grabbed until they land.
        #expect(a.center == mouth && a.isInFlight)
    }

    @Test func openPanelsStayOnScreen() {
        let stage = stage()
        let bubble = add(stage, x: 1190)
        stage.toggle(bubble)
        #expect(bubble.isOpen)
        #expect(bubble.frame.maxX <= stage.size.width)
        stage.toggle(bubble)
        #expect(!bubble.isOpen)
    }
}
