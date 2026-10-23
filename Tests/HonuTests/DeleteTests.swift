import Foundation
import Testing

@testable import Honu

/// Deleting bubbles by dragging them to the octopus, and taking them back.
@MainActor
struct DeleteTests {
    private let shell = makeShell()

    @Test func theOctopusComesUpOnlyForADragAndSinksWhenItIsDroppedElsewhere() {
        let bubble = shell.addNote()
        let home = bubble.center
        let aside = CGPoint(x: home.x + 100, y: home.y)
        shell.dragBubble(bubble, by: CGSize(width: 30, height: 0), pointer: home)
        #expect(!shell.octopus.isSummoned, "came up for a nudge")
        shell.dragBubble(bubble, by: CGSize(width: 100, height: 0), pointer: aside)
        #expect(shell.octopus.isSummoned && shell.octopus.offer == .bubble)
        #expect(!bubble.isDoomed && !shell.octopus.isEager)

        shell.endBubbleDrag(pointer: aside)
        #expect(!bubble.isSwallowed && bubble.center == aside)
        #expect(!shell.octopus.isSummoned && !shell.trash.canUndo)
        #expect(!shell.octopus.inReach(shell.octopus.middle), "stayed up")
    }

    @Test func whereThePointerIsDecidesNotWhereTheBubbleIs() {
        let bubble = shell.addNote()
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
        #expect(bubble.isSwallowed && shell.trash.canUndo)
        #expect(!shell.octopus.isEager && !shell.octopus.isSummoned)
        #expect(shell.octopus.inReach(middle), "sank while it could still undo")
    }

    @Test func undoBringsBackTheLatestDeleteFirst() {
        let a = shell.addNote(at: CGPoint(x: 400, y: 300))
        let b = shell.addNote(at: CGPoint(x: 700, y: 300))
        shell.drop(a)
        shell.drop(b)
        #expect(a.isSwallowed && b.isSwallowed)

        shell.undoDelete()
        #expect(a.isSwallowed && !b.isSwallowed)
        shell.undoDelete()
        #expect(!a.isSwallowed && !shell.trash.canUndo)
    }

    @Test func whatTheOctopusForgetsIsDeletedWithItemsNoOtherBubbleShows() throws {
        let a = shell.addNote(at: CGPoint(x: 400, y: 300))
        let b = shell.addNote(at: CGPoint(x: 700, y: 300))
        // Another bubble showing the same note as `a`.
        let twin = shell.addBubble(
            showing: a.target.item, of: shell.notes, at: CGPoint(x: 400, y: 600), fresh: false)
        shell.drop(a)
        shell.drop(b)

        shell.tick(at: now() + Bubble.swallowSeconds + Trash.undoSeconds + 1)
        #expect(shell.stage.bubbles.map(\.id) == [twin.id])
        #expect(shell.notes.items == [a.target.item], "kept a note no bubble shows, or lost one")
        #expect(!shell.trash.canUndo)
    }
}
