import Foundation
import Testing

@testable import Honu

/// Deleting bubbles by dragging them to the octopus, and taking them back.
@MainActor
struct DeleteTests {
    private let shell = makeShell()

    /// A note's bubble, at rest at `center`.
    private func note(at center: CGPoint = CGPoint(x: 600, y: 300)) -> Bubble {
        let notes = shell.registry.app(AppID("notes"))!
        return shell.addBubble(showing: notes.create(), of: notes, at: center, fresh: false)
    }

    /// Drags `bubble` far enough to call the octopus up, then drops it there.
    private func drop(_ bubble: Bubble) {
        shell.dragBubble(bubble, by: CGSize(width: 60, height: 0), pointer: bubble.center)
        let mouth = shell.octopus.middle
        shell.dragBubble(bubble, by: CGSize(width: 60, height: 0), pointer: mouth)
        shell.endBubbleDrag(pointer: mouth)
    }

    @Test func theOctopusComesUpOnlyForADragAndSinksWhenItIsDroppedElsewhere() {
        let bubble = note()
        let home = bubble.center
        let aside = CGPoint(x: home.x + 100, y: home.y)
        shell.dragBubble(bubble, by: CGSize(width: 30, height: 0), pointer: home)
        #expect(!shell.octopus.isSummoned, "came up for a nudge")
        shell.dragBubble(bubble, by: CGSize(width: 100, height: 0), pointer: aside)
        #expect(shell.octopus.isSummoned && shell.octopus.offer == .bubble)
        #expect(!bubble.isDoomed && !shell.octopus.isEager)

        shell.endBubbleDrag(pointer: aside)
        #expect(!bubble.isSwallowed && bubble.center == aside)
        #expect(!shell.octopus.isSummoned && !shell.octopus.canUndo)
        #expect(!shell.octopus.inReach(shell.octopus.middle), "stayed up")
    }

    @Test func whereThePointerIsDecidesNotWhereTheBubbleIs() {
        let bubble = note()
        let home = bubble.center
        let far = CGPoint(x: 100, y: 100)
        shell.dragBubble(bubble, by: CGSize(width: 100, height: 0), pointer: far)
        let middle = shell.octopus.middle
        // The bubble over the octopus, the pointer away from it.
        let onto = CGSize(width: middle.x - home.x, height: middle.y - home.y)
        shell.dragBubble(bubble, by: onto, pointer: far)
        #expect(!bubble.isDoomed && !shell.octopus.isEager)
        shell.endBubbleDrag(pointer: far)
        #expect(!bubble.isSwallowed)

        // The pointer on the octopus, the bubble away from it.
        shell.dragBubble(bubble, by: CGSize(width: -300, height: 0), pointer: far)
        shell.dragBubble(bubble, by: CGSize(width: -300, height: 0), pointer: middle)
        #expect(bubble.isDoomed && shell.octopus.isEager)
        shell.endBubbleDrag(pointer: middle)
        #expect(bubble.isSwallowed && shell.octopus.canUndo)
        #expect(!shell.octopus.isEager && !shell.octopus.isSummoned)
        #expect(shell.octopus.inReach(middle), "sank while it could still undo")
    }

    @Test func undoBringsBackTheLatestDeleteFirst() {
        let (a, b) = (note(at: CGPoint(x: 400, y: 300)), note(at: CGPoint(x: 700, y: 300)))
        drop(a)
        drop(b)
        #expect(a.isSwallowed && b.isSwallowed)

        shell.undoDelete()
        #expect(a.isSwallowed && !b.isSwallowed)
        shell.undoDelete()
        #expect(!a.isSwallowed && !shell.octopus.canUndo)
    }

    @Test func whatTheOctopusForgetsIsDeletedWithItemsNoOtherBubbleShows() throws {
        let notes = try #require(shell.registry.app(AppID("notes")))
        let (a, b) = (note(at: CGPoint(x: 400, y: 300)), note(at: CGPoint(x: 700, y: 300)))
        // Another bubble showing the same note as `a`.
        let twin = shell.addBubble(
            showing: a.target.item, of: notes, at: CGPoint(x: 400, y: 600), fresh: false)
        drop(a)
        drop(b)

        shell.tick(at: now() + Bubble.swallowSeconds + Octopus.undoSeconds + 1)
        #expect(shell.stage.bubbles.map(\.id) == [twin.id])
        #expect(notes.items == [a.target.item], "kept a note no bubble shows, or lost one")
        #expect(!shell.octopus.canUndo)
    }
}
