import CoreGraphics
import Testing

@testable import Honu

@MainActor
struct TrashTests {
    @Test func swallowedBubbleCanBeBroughtBackUntilItIsTooLate() {
        let trash = Trash()
        let (bubble, home, time) = (BubbleID(rawValue: 7), CGPoint(x: 400, y: 300), 1000.0)
        trash.swallow(bubble, home: home, at: time)
        #expect(trash.forget(at: time + 1).isEmpty && trash.canUndo)

        let spat = trash.spitBack(at: time + 1)
        #expect(spat?.morsels == [Trash.Swallowed.Morsel(bubble: bubble, home: home)])
        #expect(!trash.canUndo)

        trash.swallow(bubble, home: home, at: time + 2)
        #expect(trash.forget(at: time + 2 + Trash.undoSeconds + 1).flatMap(\.bubbles) == [bubble])
        #expect(!trash.canUndo, "kept the bubble too long")
        #expect(trash.spitBack(at: time + 10) == nil)
    }

    @Test func aMicroappIsSwallowedWithItsBubblesInOneGulp() {
        let trash = Trash()
        let morsels = [
            Trash.Swallowed.Morsel(bubble: BubbleID(rawValue: 1), home: CGPoint(x: 1, y: 1)),
            Trash.Swallowed.Morsel(bubble: BubbleID(rawValue: 2), home: CGPoint(x: 2, y: 2)),
        ]
        trash.swallow(morsels, microapp: "A1", at: 1000)
        #expect(trash.canUndo)
        let spat = trash.spitBack(at: 1001)
        #expect(spat?.morsels == morsels && spat?.microapp == "A1")

        // Even a microapp with no bubble left can be brought back.
        trash.swallow([], microapp: "B2", at: 1002)
        #expect(trash.canUndo)
        let gone = trash.forget(at: 1002 + Trash.undoSeconds + 1)
        #expect(gone.map(\.microapp) == ["B2"] && gone.flatMap(\.bubbles).isEmpty)
    }

    @Test func gulpsComeBackLastFirstAndAreForgottenTogether() {
        let trash = Trash()
        let (a, b) = (BubbleID(rawValue: 1), BubbleID(rawValue: 2))
        let kept = Bubble.swallowSeconds + Trash.undoSeconds
        trash.swallow(a, home: .zero, at: 1000)
        // A gulp keeps the one before it for as long as itself.
        trash.swallow(b, home: .zero, at: 1000 + Trash.undoSeconds)
        #expect(trash.forget(at: 1000 + kept + 1).isEmpty, "forgot the first gulp alone")

        let time = 1000 + Trash.undoSeconds + 1
        #expect(trash.spitBack(at: time)?.bubbles == [b])
        // Spitting one back leaves time to bring back the one before it.
        #expect(trash.forget(at: time + Trash.undoSeconds - 1).isEmpty)
        #expect(trash.spitBack(at: time + 1)?.bubbles == [a])
        #expect(!trash.canUndo)

        trash.swallow(a, home: .zero, at: 2000)
        trash.swallow(b, home: .zero, at: 2001)
        #expect(trash.forget(at: 2001 + kept).flatMap(\.bubbles) == [a, b])
        #expect(!trash.canUndo)
    }
}
