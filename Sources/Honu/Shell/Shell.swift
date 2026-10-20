import SwiftUI

/// What is under a point, from the top layer down.
enum Hit {
    case popup
    case turtle
    case octopus
    case bubble(Bubble)
    case nothing
}

/// What the turtle has open, where it was clicked: its launcher on a click,
/// or the system menu on a right click.
enum Popup: Equatable {
    case launcher(at: CGPoint)
    case system(at: CGPoint)
}

/// One tile of the turtle's launcher, which starts something new.
struct LauncherTile: Identifiable, Equatable {
    enum Kind: Hashable {
        /// A new item of a built-in microapp.
        case stock(AppID)
        /// A new instance of the installed microapp whose folder is so named.
        case installed(String)
        /// A new microapp, to be described.
        case make
    }

    let kind: Kind
    let label: String
    let symbol: String

    var id: Kind { kind }
}

/// The shell: the whole app inside the window. It wires the microapps, the
/// stage of bubbles, the turtle and its launcher, and the octopus together, and
/// routes what the user does between them.
@Observable
@MainActor
final class Shell {
    let registry: Registry
    let stage: Stage
    let turtle: Turtle
    let octopus: Octopus
    /// The microapp that makes microapps, which the launcher's **+** starts.
    let maker: MakerApp
    /// What the turtle has open, if anything.
    private(set) var popup: Popup?
    /// The launcher tile being dragged toward the octopus, and where the
    /// pointer is.
    private(set) var tileDrag: (tile: LauncherTile, pointer: CGPoint)?
    /// A tile dropped on the octopus, going down into its mouth along
    /// `flight`, which started at `start`.
    private(set) var swallowedTile: (tile: LauncherTile, flight: Flight, start: TimeInterval)?
    /// How big a tile is drawn while held over the octopus.
    static let eagerTileScale: CGFloat = 0.7
    /// The newest bubble the turtle spat out, which takes text typed before
    /// its field takes the focus.
    @ObservationIgnored private var typeAheadTarget: BubbleID?
    /// Where the turtle was when the current drag of it began.
    @ObservationIgnored private var turtleDragStart: CGPoint?
    @ObservationIgnored private let autosave: Autosave
    /// When `tick` last ran, for how far to move things.
    @ObservationIgnored private var lastTick: TimeInterval?
    /// Each bubble's own undo history, made when first asked for.
    @ObservationIgnored private var undoManagers: [BubbleID: UndoManager] = [:]

    /// How far a bubble must be dragged before the octopus comes up, so
    /// nudging a bubble into place does not call it.
    private static let summonDistance: CGFloat = 40

    /// A shell for a screen of `size`, saving to and restoring from
    /// `storeURL`, whose microapps share `services`.
    init(
        size: CGSize, storeURL: URL = Autosave.storeURL, services: Services = .live()
    ) {
        autosave = Autosave(url: storeURL)
        maker = MakerApp(root: MakerApp.root(for: storeURL), services: services)
        registry = Registry([NotesApp(), AskApp(services: services), WebApp(), maker])
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
        popup != nil || stage.isDragging || turtleDragStart != nil
    }

    /// What is under `point`: an open menu takes everything, then the turtle
    /// and the octopus, then the bubbles.
    func hit(_ point: CGPoint) -> Hit {
        if popup != nil {
            .popup
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

    // MARK: The turtle and its launcher

    /// Opens the turtle's launcher at `point`, with a little hop.
    func clickTurtle(at point: CGPoint) {
        turtle.hop()
        popup = .launcher(at: point)
    }

    /// Opens the system menu at `point`, with a little hop.
    func rightClickTurtle(at point: CGPoint) {
        turtle.hop()
        popup = .system(at: point)
    }

    /// Closes whichever menu is open, letting go of any tile being dragged.
    func closePopup() {
        popup = nil
        if tileDrag != nil {
            tileDrag = nil
            octopus.isEager = false
            octopus.summon(false, turtle: turtle.center)
        }
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

    /// Carries out the launcher tile `tile`.
    func choose(_ tile: LauncherTile.Kind) {
        popup = nil
        switch tile {
        case .stock(let app): start(app)
        case .installed(let name): launch(name)
        case .make: start(maker.id)
        }
    }

    /// Starts a new item in microapp `id` and has the turtle spit out a
    /// bubble showing it, which opens into its panel when it lands.
    func start(_ id: AppID) {
        guard let app = registry.app(id) else { return }
        spit(app.create(), of: app)
    }

    /// Starts a new instance of the installed microapp whose folder is named
    /// `name`, and has the turtle spit out a bubble showing it.
    func launch(_ name: String) {
        guard let item = maker.launch(name) else { return }
        spit(item, of: maker)
    }

    /// Closes the launcher and starts a new instance of the installed
    /// microapp whose folder is named `name`, to ask Claude to change it:
    /// its bubble opens with the cursor in its change field.
    func modify(_ name: String) {
        popup = nil
        guard let item = maker.launch(name, toModify: true) else { return }
        spit(item, of: maker)
    }

    /// Has the turtle spit out a bubble showing `item`, just made, which
    /// opens into its panel when it lands and takes what is typed until then.
    private func spit(_ item: ItemID, of app: any MicroApp) {
        let bubble = addBubble(showing: item, of: app, at: turtle.center, fresh: true)
        stage.spitPanel(bubble, from: turtle.spit())
        typeAheadTarget = bubble.id
    }

    /// Adds a bubble at `center` showing `item` of `app`, looking the way
    /// `app` says, with a view state of its own. A `fresh` item, just
    /// created, may take the focus.
    func addBubble(
        showing item: ItemID, of app: any MicroApp, at center: CGPoint, fresh: Bool
    ) -> Bubble {
        stage.add(
            target: ViewTarget(app: app.id, item: item), center: center,
            appearance: app.appearance(of: item),
            viewState: app.newViewState(for: item, fresh: fresh))
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
        app.anyTypeAhead(text, into: bubble.target.item, viewState: bubble.viewState)
        return true
    }

    // MARK: Bubbles and the octopus

    /// The undo history of `bubble`. Every bubble keeps its own, though they
    /// share one window, so ⌘Z undoes typing in the bubble with the focus
    /// rather than in whichever was edited last. It outlives the bubble's
    /// content, so closing and opening the bubble keeps it.
    func undoManager(for bubble: Bubble) -> UndoManager {
        if let manager = undoManagers[bubble.id] {
            return manager
        }
        let manager = UndoManager()
        undoManagers[bubble.id] = manager
        return manager
    }

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

    /// Drags launcher `tile`, picked up at `start`, with the pointer now at
    /// `pointer`. Only an installed microapp's tile moves, calling up the
    /// octopus to uninstall it once dragged far enough; returns whether it
    /// does.
    func dragTile(_ tile: LauncherTile, from start: CGPoint, to pointer: CGPoint) -> Bool {
        guard case .installed = tile.kind else { return false }
        tileDrag = (tile, pointer)
        octopus.isEager = octopus.inReach(pointer)
        let summoned = (pointer - start).length > Self.summonDistance
        octopus.summon(summoned, turtle: turtle.center, offer: .microapp)
        return true
    }

    /// Lets go of the dragged tile with the pointer at `pointer` at `time`:
    /// on the octopus, the tile goes down its mouth, its microapp is
    /// uninstalled, and the launcher closes; elsewhere, the tile goes back.
    func endTileDrag(at pointer: CGPoint, time: TimeInterval = now()) {
        guard let (tile, _) = tileDrag else { return }
        tileDrag = nil
        octopus.isEager = false
        if octopus.inReach(pointer) {
            uninstall(tile, from: pointer, scale: Self.eagerTileScale, at: time)
        }
        octopus.summon(false, turtle: turtle.center)
    }

    /// Uninstalls the microapp of launcher `tile`, at `center` and drawn at
    /// `scale`, at `time`: the launcher closes, and the tile goes down the
    /// octopus's mouth with the microapp's bubbles.
    func uninstall(
        _ tile: LauncherTile, from center: CGPoint, scale: CGFloat = 1,
        at time: TimeInterval = now()
    ) {
        guard case .installed(let name) = tile.kind else { return }
        popup = nil
        swallowedTile = (
            tile,
            Flight(kind: .swallow(fromScale: scale), from: center, to: octopus.mouth),
            time
        )
        uninstall(name, at: time)
    }

    /// Uninstalls the microapp whose folder is named `name`: its tile leaves
    /// the launcher, and the octopus swallows it with every bubble of it,
    /// keeping them for a while in case the user takes it back.
    func uninstall(_ name: String, at time: TimeInterval = now()) {
        guard let microapp = maker.library.first(where: { $0.folder.name == name }) else { return }
        maker.withdraw(name)
        let targets = Set(maker.items(of: microapp).map { ViewTarget(app: maker.id, item: $0) })
        var morsels: [Octopus.Swallowed.Morsel] = []
        for bubble in stage.bubbles where targets.contains(bubble.target) && !bubble.isSwallowed {
            morsels.append(Octopus.Swallowed.Morsel(bubble: bubble.id, home: bubble.destination))
            stage.swallow(bubble, into: octopus.mouth)
        }
        octopus.swallow(morsels, microapp: name, at: time)
        octopus.summon(false, turtle: turtle.center)
    }

    /// Has the octopus spit back what it swallowed last, if it still can:
    /// a bubble, or a microapp with its bubbles, whose tile comes back.
    func undoDelete() {
        guard let swallowed = octopus.spitBack() else { return }
        if let microapp = swallowed.microapp {
            maker.reinstate(microapp)
        }
        for morsel in swallowed.morsels {
            if let bubble = stage.bubble(morsel.bubble) {
                stage.spitBack(bubble, from: octopus.mouth, to: morsel.home)
            }
        }
    }

    /// Catches up on what happens over time: moves the bubbles, deletes for
    /// good the bubbles and microapps the octopus forgets, and saves what
    /// changed. Called many times a second.
    func tick(at time: TimeInterval = now()) {
        // A long pause, such as while the Mac slept, moves nothing far.
        let dt = min(time - (lastTick ?? time), 1.0 / 30)
        lastTick = time
        updateApps()
        stage.step(time: time, dt: dt)
        if let swallowed = swallowedTile, time - swallowed.start >= swallowed.flight.seconds {
            swallowedTile = nil
        }
        for swallowed in octopus.forget(at: time) {
            for id in swallowed.bubbles {
                undoManagers[id] = nil
                if let bubble = stage.remove(id), !stage.shows(bubble.target) {
                    registry.remove(bubble.target)
                }
            }
            if let microapp = swallowed.microapp {
                maker.uninstall(microapp)
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
            if let size = registry.appearance(of: bubble.target)?.panelSize,
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
}
