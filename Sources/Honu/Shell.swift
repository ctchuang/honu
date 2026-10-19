import SwiftUI

/// What is under a point, from the top layer down.
enum Hit {
    case menu
    case turtle
    case octopus
    case bubble(Bubble)
    case nothing
}

/// The shell: the whole app inside the window. It wires the microapps, the
/// stage of bubbles, the turtle and its menu, and the octopus together, and
/// routes what the user does between them.
@Observable
@MainActor
final class Shell {
    let registry: Registry
    let stage: Stage
    let turtle: Turtle
    let octopus: Octopus
    /// Where the turtle's menu is open (its top-left corner), if it is.
    private(set) var menu: CGPoint?
    /// The newest bubble the turtle spat out, which takes text typed before
    /// its field takes the focus.
    @ObservationIgnored private var typeAheadTarget: BubbleID?
    /// Where the turtle was when the current drag of it began.
    @ObservationIgnored private var turtleDragStart: CGPoint?
    @ObservationIgnored private let autosave: Autosave
    /// When `tick` last ran, for how far to move things.
    @ObservationIgnored private var lastTick: TimeInterval?

    /// How far a bubble must be dragged before the octopus comes up, so
    /// nudging a bubble into place does not call it.
    private static let summonDistance: CGFloat = 40

    /// A shell for a screen of `size`, saving to and restoring from
    /// `storeURL`, whose microapps share `services`.
    init(
        size: CGSize, storeURL: URL = Autosave.storeURL, services: Services = .live()
    ) {
        autosave = Autosave(url: storeURL)
        registry = Registry([NotesApp(), AskApp(services: services), WebApp()])
        stage = Stage(size: size)
        turtle = Turtle(stageSize: size)
        octopus = Octopus(stageSize: size)
        if let state = autosave.restore() {
            restore(state)
        }
    }

    /// Whether the user is in the middle of something that takes every click,
    /// like a native menu: a click outside an open menu only closes it.
    var takesEveryClick: Bool {
        menu != nil || stage.isDragging || turtleDragStart != nil
    }

    /// What is under `point`: the open menu takes everything, then the turtle
    /// and the octopus, then the bubbles.
    func hit(_ point: CGPoint) -> Hit {
        if menu != nil {
            .menu
        } else if turtle.contains(point) {
            .turtle
        } else if octopus.contains(point) {
            .octopus
        } else if let bubble = stage.bubble(at: point) {
            .bubble(bubble)
        } else {
            .nothing
        }
    }

    /// Whether clicks at `point` are Honu's rather than the apps' below.
    func takesClick(at point: CGPoint) -> Bool {
        if takesEveryClick { return true }
        if case .nothing = hit(point) { return false }
        return true
    }

    // MARK: The turtle and its menu

    /// Opens the turtle's menu at `point`, with a little hop.
    func clickTurtle(at point: CGPoint) {
        turtle.hop()
        // Keep the whole menu on screen.
        menu = CGPoint(
            x: min(point.x, stage.size.width - TurtleMenu.width - 8),
            y: min(point.y, stage.size.height - TurtleMenu.estimatedHeight - 8))
    }

    func closeMenu() {
        menu = nil
    }

    func dragTurtle(by translation: CGSize) {
        let start = turtleDragStart ?? turtle.origin
        turtleDragStart = start
        turtle.move(to: CGPoint(x: start.x + translation.width, y: start.y + translation.height))
    }

    func endTurtleDrag() {
        turtleDragStart = nil
        save()
    }

    /// Carries out the menu item for microapp `app`.
    func choose(_ app: AppID) {
        menu = nil
        start(app)
    }

    /// Starts a new item in microapp `id` and has the turtle spit out a
    /// bubble showing it, which opens into its panel when it lands.
    func start(_ id: AppID) {
        guard let app = registry.app(id) else { return }
        let item = app.create()
        let bubble = stage.add(
            target: ViewTarget(app: id, item: item), center: turtle.center,
            appearance: app.appearance(of: item),
            viewState: app.newViewState(for: item, fresh: true))
        stage.spitPanel(bubble, from: turtle.spit())
        typeAheadTarget = bubble.id
    }

    /// Hands `text`, typed while no field has the focus, to the newest bubble
    /// the turtle spat out, as long as its field has yet to take the focus.
    /// Returns whether a bubble took it.
    func type(_ text: String) -> Bool {
        guard let id = typeAheadTarget, let bubble = stage.bubble(id), !bubble.isSwallowed,
            (bubble.viewState as? FocusTaking)?.focusPending == true,
            let app = registry.app(bubble.target.app)
        else {
            typeAheadTarget = nil
            return false
        }
        app.typeAhead(text, into: bubble.target.item, viewState: bubble.viewState)
        return true
    }

    // MARK: Bubbles and the octopus

    /// Any press on a bubble brings it to the front, including presses on an
    /// open bubble's content, which SwiftUI's gestures never see.
    func press(at point: CGPoint) {
        if case .bubble(let bubble) = hit(point) {
            stage.raise(bubble)
        }
    }

    /// Moves `bubble`, picking it up if it is not yet. Holding it over the
    /// octopus shrinks it, and letting go there deletes it. Where the pointer
    /// is decides, not where the bubble is, so only a deliberate drop deletes.
    func dragBubble(
        _ bubble: Bubble, by translation: CGSize, velocity: CGSize = .zero, pointer: CGPoint
    ) {
        if !stage.isDragging {
            stage.startDrag(bubble)
        }
        let doomed = octopus.inReach(pointer)
        octopus.isEager = doomed
        stage.dragged(by: translation, velocity: velocity, doomed: doomed)
        let summoned = (stage.dragDistance ?? 0) > Self.summonDistance
        octopus.summon(summoned, turtle: turtle.center)
    }

    func endBubbleDrag(pointer: CGPoint) {
        let doomed = octopus.inReach(pointer)
        octopus.isEager = false
        guard let (bubble, home) = stage.endDrag() else { return }
        autosave.moved()
        if doomed {
            octopus.swallow(bubble.id, home: home)
            stage.swallow(bubble, into: octopus.mouth)
        }
        octopus.summon(false, turtle: turtle.center)
    }

    /// Has the octopus spit back the bubble it swallowed last, if it still can.
    func undoDelete() {
        guard let swallowed = octopus.spitBack(), let bubble = stage.bubble(swallowed.bubble)
        else { return }
        stage.spitBack(bubble, from: octopus.mouth, to: swallowed.home)
    }

    /// Catches up on what happens over time: moves the bubbles, deletes for
    /// good the bubbles the octopus forgets, and saves what changed. Called
    /// many times a second.
    func tick(at time: TimeInterval = now()) {
        // A long pause, such as while the Mac slept, moves nothing far.
        let dt = min(time - (lastTick ?? time), 1.0 / 30)
        lastTick = time
        updateApps()
        stage.step(time: time, dt: dt)
        for id in octopus.forget() {
            if let bubble = stage.remove(id), !stage.shows(bubble.target) {
                registry.remove(bubble.target)
            }
        }
        autosave.tick(snapshot)
    }

    /// Lets the microapps catch up, shows on each bubble what its item is
    /// doing (it breathes while busy, and an open panel takes the size its
    /// microapp asks for), and plays the motions they ask for.
    private func updateApps() {
        for effect in registry.update() {
            switch effect {
            case .motion(let target, let motion):
                for bubble in stage.bubbles where bubble.target == target {
                    bubble.play(motion)
                }
            }
        }
        for bubble in stage.bubbles {
            let busy = registry.isBusy(bubble.target)
            if bubble.isBusy != busy {
                bubble.isBusy = busy
            }
            let app = registry.app(bubble.target.app)
            if let size = app?.appearance(of: bubble.target.item).panelSize,
                size != bubble.panelSize
            {
                withAnimation(.smooth(duration: 0.25)) { bubble.panelSize = size }
            }
        }
    }

    // MARK: Saving

    /// Saves now, as when quitting.
    func save() {
        autosave.save(snapshot())
    }

    /// What to keep for the next launch: places relative to the center of the
    /// screen, so they come back in place on a screen of another size.
    func snapshot() -> SavedState {
        let center = stage.center
        var state = SavedState()
        state.turtle = turtle.rest.map { $0 - center }
        // A bubble still in the octopus when Honu quits counts as deleted.
        state.bubbles = stage.bubbles.filter { !$0.isSwallowed }.map {
            // Where it is going, so a bubble saved mid-flight comes back where it lands.
            SavedBubble(target: $0.target, offset: $0.destination - center, isOpen: $0.isOpen)
        }
        for app in registry.apps {
            if let data = app.save(), let json = String(data: data, encoding: .utf8) {
                state.apps[app.id.rawValue] = json
            }
        }
        return state
    }

    /// Puts back what was saved on the last launch, without the focus, and
    /// deletes items no bubble showed, such as one still in the octopus.
    private func restore(_ state: SavedState) {
        let center = stage.center
        if let offset = state.turtle {
            turtle.move(to: center + offset)
        }
        for app in registry.apps {
            if let json = state.apps[app.id.rawValue] {
                app.load(Data(json.utf8))
            }
        }
        for saved in state.bubbles where registry.has(saved.target) {
            guard let app = registry.app(saved.target.app) else { continue }
            let item = saved.target.item
            let bubble = stage.add(
                target: saved.target, center: center + saved.offset,
                appearance: app.appearance(of: item),
                viewState: app.newViewState(for: item, fresh: false))
            bubble.isOpen = saved.isOpen
        }
        for app in registry.apps {
            for item in app.items where !stage.shows(ViewTarget(app: app.id, item: item)) {
                app.remove(item)
            }
        }
    }
}
