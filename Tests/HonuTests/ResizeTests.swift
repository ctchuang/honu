import Foundation
import Testing

@testable import Honu

@MainActor
struct ResizeTests {
    /// A screen 1200 by 800 points, which keeps bubbles 16 points from its edges.
    private let stage = Stage(size: CGSize(width: 1200, height: 800))

    /// A bubble of the default size, 380 by 300 points, in the middle of the
    /// screen: from 410 to 790 across and 250 to 550 down.
    private func bubble() -> Bubble {
        stage.add(
            target: ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1)),
            center: CGPoint(x: 600, y: 400), appearance: Appearance(), viewState: nil)
    }

    private func resize(_ bubble: Bubble, _ edges: Edges, by translation: CGSize) {
        stage.startResize(bubble, edges: edges)
        stage.resized(by: translation)
        stage.endResize()
    }

    @Test func theOppositeEdgeStaysPut() {
        let bubble = bubble()
        resize(bubble, .right, by: CGSize(width: 100, height: 30))
        #expect(bubble.frame == CGRect(x: 410, y: 250, width: 480, height: 300))
        #expect(bubble.userSize == CGSize(width: 480, height: 300))

        resize(bubble, .left, by: CGSize(width: -50, height: 0))
        #expect(bubble.frame == CGRect(x: 360, y: 250, width: 530, height: 300))
    }

    @Test func aCornerResizesBothWays() {
        let bubble = bubble()
        resize(bubble, .topLeft, by: CGSize(width: -40, height: -60))
        #expect(bubble.frame == CGRect(x: 370, y: 190, width: 420, height: 360))
        resize(bubble, .bottomRight, by: CGSize(width: 20, height: 10))
        #expect(bubble.frame == CGRect(x: 370, y: 190, width: 440, height: 370))
    }

    @Test func theSizeStaysWithinLimitsAndOnScreen() {
        let bubble = bubble()
        resize(bubble, .bottomRight, by: CGSize(width: -1000, height: -1000))
        #expect(bubble.frame == CGRect(origin: CGPoint(x: 410, y: 250), size: bubble.minSize))

        resize(bubble, .topLeft, by: CGSize(width: -2000, height: -2000))
        #expect(bubble.frame.origin == CGPoint(x: 16, y: 16))
        resize(bubble, .bottomRight, by: CGSize(width: 2000, height: 2000))
        #expect(bubble.frame == CGRect(x: 16, y: 16, width: 1168, height: 768))
    }

    @Test func aBubbleNeverResizedFollowsItsMicroapp() {
        let bubble = bubble()
        #expect(!stage.zoom(bubble), "zoomed without a size of the user's")
        bubble.microappSize = CGSize(width: 400, height: 500)
        #expect(bubble.size == CGSize(width: 400, height: 500))
    }

    @Test func aResizedBubbleKeepsItsSizeUntilZoomed() {
        let bubble = bubble()
        resize(bubble, .right, by: CGSize(width: 100, height: 0))
        bubble.microappSize = CGSize(width: 400, height: 500)
        #expect(bubble.size == CGSize(width: 480, height: 300), "the microapp resized it")

        #expect(stage.zoom(bubble))
        #expect(bubble.isZoomed && bubble.size == CGSize(width: 400, height: 500))
        // Zoomed, it follows its microapp again.
        bubble.microappSize = CGSize(width: 420, height: 520)
        #expect(bubble.size == CGSize(width: 420, height: 520))

        #expect(stage.zoom(bubble))
        #expect(!bubble.isZoomed && bubble.size == CGSize(width: 480, height: 300))
    }

    @Test func resizingAZoomedBubbleMakesANewUserSize() {
        let bubble = bubble()
        resize(bubble, .right, by: CGSize(width: 100, height: 0))
        stage.zoom(bubble)
        resize(bubble, .bottom, by: CGSize(width: 0, height: 20))
        #expect(!bubble.isZoomed)
        #expect(bubble.userSize == CGSize(width: 380, height: 320))
    }

    @Test func zoomingKeepsTheBubbleOnScreen() {
        let bubble = bubble()
        resize(bubble, .bottomRight, by: CGSize(width: -140, height: -140))
        bubble.center = CGPoint(x: 1050, y: 400)
        stage.zoom(bubble)
        #expect(bubble.frame.maxX <= stage.size.width - 16)
    }

    @Test func theRimResizesItsEdgesAndCorners() {
        let bubble = bubble()
        #expect(bubble.rimEdges(at: CGPoint(x: 785, y: 400)) == .right)
        #expect(bubble.rimEdges(at: CGPoint(x: 415, y: 400)) == .left)
        #expect(bubble.rimEdges(at: CGPoint(x: 600, y: 253)) == .top)
        #expect(bubble.rimEdges(at: CGPoint(x: 600, y: 545)) == .bottom)
        #expect(bubble.rimEdges(at: CGPoint(x: 422, y: 262)) == .topLeft)
        #expect(bubble.rimEdges(at: CGPoint(x: 778, y: 538)) == .bottomRight)
        #expect(bubble.rimEdges(at: CGPoint(x: 778, y: 262)) == .topRight)
        #expect(bubble.rimEdges(at: CGPoint(x: 422, y: 538)) == .bottomLeft)
    }

    @Test func theTitleTheContentAndPastTheOutlineAreNotRim() {
        let bubble = bubble()
        #expect(bubble.rimEdges(at: CGPoint(x: 600, y: 265)).isEmpty, "the title")
        #expect(bubble.rimEdges(at: CGPoint(x: 600, y: 400)).isEmpty, "the content")
        #expect(bubble.rimEdges(at: CGPoint(x: 411, y: 251)).isEmpty, "past the rounded corner")
        #expect(bubble.rimEdges(at: CGPoint(x: 795, y: 400)).isEmpty, "outside")
    }

    @Test func aResizedBubbleComesToTheTopAndCannotBeDraggedMeanwhile() {
        let resized = bubble()
        let other = bubble()
        stage.startResize(resized, edges: .right)
        #expect(stage.bubbles.last === resized && stage.isResizing)
        stage.startDrag(other)
        #expect(!stage.isDragging)
        stage.endResize()
        #expect(!stage.isResizing)
    }
}

@MainActor
struct ShellResizeTests {
    /// Ticks `shell` for a second from `start`, so new bubbles land.
    private func land(_ shell: Shell, from start: TimeInterval = 0) {
        for frame in 0...60 {
            shell.tick(at: start + Double(frame) / 60)
        }
    }

    private func widen(_ shell: Shell, _ bubble: Bubble, by width: CGFloat) {
        shell.resizeBubble(bubble, edges: .right, by: CGSize(width: width, height: 0))
        shell.endBubbleResize()
    }

    private func clockPage(size: String) -> String {
        """
        <!doctype html><html><head><title>Clock</title>
        <meta name="honu-size" content="\(size)"></head><body></body></html>
        """
    }

    /// Drags `bubble` from `start` by `translation` and lets go.
    private func drag(_ shell: Shell, _ bubble: Bubble, from start: CGPoint, by translation: CGSize)
    {
        let pointer = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        shell.dragBubble(
            bubble, from: start, by: translation, velocity: .zero, pointer: pointer)
        shell.endBubbleDrag(pointer: pointer)
    }

    @Test func draggingTheRimResizesAndDraggingTheTitleMoves() {
        let shell = makeShell()
        let bubble = shell.addNote(at: CGPoint(x: 600, y: 400))
        drag(shell, bubble, from: CGPoint(x: 785, y: 400), by: CGSize(width: 40, height: 10))
        #expect(bubble.frame == CGRect(x: 410, y: 250, width: 420, height: 300))

        drag(shell, bubble, from: CGPoint(x: 600, y: 265), by: CGSize(width: -30, height: 20))
        #expect(bubble.frame == CGRect(x: 380, y: 270, width: 420, height: 300))
        #expect(!shell.stage.isDragging && !shell.stage.isResizing)
    }

    @Test func resizingOverTheOctopusDoesNotDelete() throws {
        let shell = makeShell()
        let bubble = shell.addNote(at: CGPoint(x: 600, y: 400))
        let rim = CGPoint(x: 600, y: 545)
        let mouth = shell.octopus.middle
        drag(shell, bubble, from: rim, by: CGSize(width: mouth.x - rim.x, height: mouth.y - rim.y))
        #expect(!bubble.isSwallowed && !shell.trash.canUndo)
        #expect(bubble.userSize != nil)
    }

    @Test func aChatsGrowingAnswerDoesNotResizeAResizedBubble() throws {
        let shell = makeShell()
        shell.start(AppID("ask"))
        land(shell)
        let bubble = try #require(shell.stage.bubbles.last)
        widen(shell, bubble, by: 60)
        let chosen = bubble.size

        shell.asks.chats[bubble.target.item]?.contentHeight = 300
        shell.tick(at: 2)
        #expect(bubble.size == chosen, "the answer resized it")
        #expect(bubble.microappSize.height == 300 + AskApp.chromeHeight)

        shell.zoom(bubble)
        #expect(bubble.size == bubble.microappSize)
        shell.zoom(bubble)
        #expect(bubble.size == chosen)
    }

    @Test func aBubbleTakesItsMicroappsMinimum() throws {
        let claude = FakeClaude()
        let shell = makeShell(claude: claude)
        let (bubble, _) = try shell.makeMicroapp("Clock", claude: claude)
        shell.tick(at: 2)
        #expect(bubble.minSize == AppSource.minSize + MakerApp.chrome)
    }

    @Test func aPageResizesItsBubbleOnlyUntilTheUserDoes() throws {
        let claude = FakeClaude()
        let shell = makeShell(claude: claude)
        let (bubble, _) = try shell.makeMicroapp("Clock", claude: claude)
        let item = bubble.target.item
        shell.maker.resize(item, to: CGSize(width: 400, height: 300))
        land(shell, from: 2)
        #expect(bubble.size == CGSize(width: 400, height: 300) + MakerApp.chrome)

        widen(shell, bubble, by: 50)
        let chosen = bubble.size
        shell.maker.resize(item, to: CGSize(width: 500, height: 500))
        shell.tick(at: 4)
        #expect(bubble.size == chosen, "honu.resize won over the user")

        // Zoomed to the page's size, it follows the page again.
        shell.zoom(bubble)
        #expect(bubble.size == CGSize(width: 500, height: 500) + MakerApp.chrome)
    }

    @Test func aDescriptionThatBecomesAPageTakesThePagesSize() throws {
        let claude = FakeClaude()
        let shell = makeShell(claude: claude)
        shell.choose(.make)
        land(shell)
        let bubble = try #require(shell.stage.bubbles.last)
        widen(shell, bubble, by: 80)
        #expect(bubble.userSize != nil)

        let microapp = try #require(shell.maker.microapp(of: bubble.target.item))
        microapp.draft = "a clock"
        shell.maker.make(bubble.target.item)
        claude.streams[0].send(.text(clockPage(size: "300x400")))
        claude.streams[0].send(.done)
        shell.tick(at: 2)
        #expect(bubble.userSize == nil && !bubble.isZoomed)
        #expect(bubble.size == CGSize(width: 300, height: 400) + MakerApp.chrome)

        // A change to the page keeps the size the user gives it.
        widen(shell, bubble, by: 40)
        let chosen = try #require(bubble.userSize)
        microapp.draft = "make it blue"
        shell.maker.change(bubble.target.item)
        claude.streams[1].send(.text(clockPage(size: "320x420")))
        claude.streams[1].send(.done)
        shell.tick(at: 3)
        #expect(bubble.size == chosen)
    }
}
