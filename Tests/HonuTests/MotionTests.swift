import Foundation
import SwiftUI
import Testing

@testable import Honu

@MainActor
struct MotionTests {
    private static let dt = 1.0 / 60

    private func bubble() -> Bubble {
        Bubble(
            id: BubbleID(rawValue: 1),
            target: ViewTarget(app: AppID("test"), item: ItemID(rawValue: 1)),
            center: CGPoint(x: 500, y: 300), appearance: Appearance(), viewState: nil)
    }

    /// Runs `bubble` for `seconds`, calling `watch` after each step.
    private func run(_ bubble: Bubble, _ seconds: Double, watch: () -> Void = {}) {
        for _ in 0..<Int(seconds / Self.dt) {
            _ = bubble.animate(dt: Self.dt)
            watch()
        }
    }

    @Test(arguments: [Motion.rise, .wobble])
    func motionsMoveTheBubbleAndReturnIt(motion: Motion) {
        let bubble = bubble()
        bubble.play(motion)
        var farthest = 0.0
        run(bubble, 2) {
            farthest = max(farthest, hypot(bubble.motionOffset.width, bubble.motionOffset.height))
        }
        #expect(farthest > 5, "moved only \(farthest)")
        #expect(bubble.motionOffset == .zero, "did not settle")
        #expect(bubble.center == CGPoint(x: 500, y: 300), "moved the bubble itself")
    }

    @Test func breathingSwellsOnlyTheGlassAndFadesOut() {
        let bubble = bubble()
        let frame = bubble.frame
        bubble.isBusy = true
        var widest: CGFloat = 0
        run(bubble, 3) {
            #expect(bubble.frame == frame, "breathing changed the hit area")
            widest = max(widest, bubble.swell)
        }
        #expect(widest > Bubble.breathPoints * 0.8, "swelled only \(widest)")
        bubble.isBusy = false
        run(bubble, 3)
        #expect(bubble.swell < 0.1)
        #expect(bubble.breath == 0)
    }
}

/// A microapp whose one item is busy and asks for a rise every update.
@MainActor
private final class Worker: MicroApp {
    let id = AppID("worker")
    let launcherLabel = "Work"
    let launcherSymbol = "hammer"
    var items: [ItemID] = [ItemID(rawValue: 1)]
    var busy = true

    func create() -> ItemID { items[0] }
    func appearance(of item: ItemID) -> Appearance { Appearance() }
    func title(of item: ItemID) -> String { "Work" }
    func content(of item: ItemID, viewState: NoViewState) -> EmptyView { EmptyView() }
    func remove(_ item: ItemID) {}
    func save() -> Data? { nil }
    func load(_ data: Data) {}
    func isBusy(_ item: ItemID) -> Bool { busy }

    func update(_ context: Context) {
        context.play(.rise, for: items[0])
    }
}

@MainActor
struct EffectTests {
    @Test func theRegistryCollectsWhatMicroappsAskFor() {
        let worker = Worker()
        let registry = Registry([worker])
        let target = ViewTarget(app: worker.id, item: worker.items[0])
        #expect(registry.update() == [.motion(target, .rise)])
        #expect(registry.isBusy(target))
        worker.busy = false
        #expect(!registry.isBusy(target))
        #expect(!registry.isBusy(ViewTarget(app: AppID("unknown"), item: target.item)))
    }
}

struct FlightTests {
    private let from = CGPoint(x: 100, y: 700)
    private let to = CGPoint(x: 400, y: 300)

    @Test func easingStartsAndEndsInPlaceAndPopsOutPastTheEnd() {
        for ease in [easeOutQuad, easeOutBack] {
            #expect(ease(0) == 0 && ease(1) == 1)
        }
        let steps = stride(from: 0.0, through: 1, by: 0.01)
        #expect(steps.map(easeOutQuad).allSatisfy { $0 <= 1 })
        #expect(steps.map(easeOutBack).contains { $0 > 1 }, "no overshoot")
    }

    @Test func aBubbleSpatOutGrowsOnTheWayAndLandsFullSize() {
        let flight = Flight(kind: .spawn(openOnLanding: true), from: from, to: to)
        #expect(flight.after(0).position == from && flight.after(0).scale == 0)
        let steps = stride(from: 0.0, through: flight.seconds, by: flight.seconds / 50)
        #expect(steps.contains { flight.after($0).scale > 1 }, "did not pop")
        let landed = flight.after(flight.seconds)
        #expect(landed.position == to && landed.scale == 1)
        // It stays where it landed, however late it is asked.
        #expect(flight.after(flight.seconds * 3).position == to)
        #expect(flight.after(-1).position == from)
    }

    @Test func aSwallowedBubbleShrinksToNothingInTheMouth() {
        let flight = Flight(kind: .swallow(fromScale: 0.7), from: from, to: to)
        #expect(flight.after(0).scale == 0.7)
        let scales = stride(from: 0.0, through: flight.seconds, by: flight.seconds / 50).map {
            flight.after($0).scale
        }
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 >= $1 }, "grew on the way")
        let gone = flight.after(flight.seconds)
        #expect(gone.position == to && gone.scale == 0)
    }
}
