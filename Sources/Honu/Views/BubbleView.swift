import SwiftUI

/// One bubble in interactive Liquid Glass, tinted the way its microapp says.
/// It shows its title (unless its content shows it) over the content its
/// microapp makes. Dragging its rim resizes it, dragging it elsewhere moves
/// it, and double-clicking its title zooms it.
struct BubbleView: View {
    let bubble: Bubble
    let shell: Shell
    let glass: Namespace.ID
    /// Where bubbles above lie, cut away from this one's glass and content.
    let cuts: [Cut]
    /// The edges of the rim the pointer is over, which set the cursor.
    private let hovered = State(initialValue: Edges())

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: bubble.cornerRadius, style: .continuous)
    }

    var body: some View {
        let appearance = shell.appearance(of: bubble)
        content(appearance: appearance, title: shell.title(of: bubble))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // While the glass wobbles like jelly, the content squashes and
            // stretches with it.
            .transformEffect(bubble.contentTransform)
            // Content below another bubble is drawn above that bubble's glass,
            // so it is cut away too.
            .clipShape(CutAway(shape: shape, outline: bubble.outline, cuts: cuts))
            .contentShape(shape)
            // The glass goes on the content itself, which keeps the content in
            // front of it; a glass layer of its own would be drawn over the
            // content. Only the glass breathes, so the content holds still.
            .glassEffect(
                glassStyle(appearance),
                in: CutAway(shape: shape, outline: bubble.outline, swell: bubble.swell, cuts: cuts)
            )
            .glassEffectID(bubble.id, in: glass)
            .onContinuousHover(coordinateSpace: .named(ShellView.space)) {
                if case .active(let point) = $0 {
                    hovered.wrappedValue = bubble.rimEdges(at: point)
                } else {
                    hovered.wrappedValue = []
                }
            }
            // The edges being resized keep their cursor wherever the pointer goes.
            .pointerStyle(
                Self.cursor(for: shell.stage.resizedEdges(of: bubble) ?? hovered.wrappedValue)
            )
            .gesture(drag)
    }

    /// The system's resize cursor for `edges`, or none off the rim.
    private static func cursor(for edges: Edges) -> PointerStyle? {
        let position: FrameResizePosition? =
            switch edges {
            case .top: .top
            case .bottom: .bottom
            case .left: .leading
            case .right: .trailing
            case .topLeft: .topLeading
            case .topRight: .topTrailing
            case .bottomLeft: .bottomLeading
            case .bottomRight: .bottomTrailing
            default: nil
            }
        return position.map { .frameResize(position: $0) }
    }

    private func glassStyle(_ appearance: Appearance) -> Glass {
        let glass: Glass = appearance.tint.map { .regular.tint($0) } ?? .regular
        return glass.interactive()
    }

    private func content(appearance: Appearance, title: String) -> some View {
        VStack(spacing: 0) {
            // Without a title, a strip of glass is left to drag the bubble
            // by, tall enough to grab below the rim.
            Text(appearance.showsTitle ? title : "")
                .font(.headline)
                .foregroundStyle(appearance.textColor)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: appearance.showsTitle ? 36 : 28)
                .contentShape(Rectangle())
                // Double-clicking the title zooms, as with a window's title bar.
                .onTapGesture(count: 2, coordinateSpace: .named(ShellView.space)) {
                    if bubble.rimEdges(at: $0).isEmpty {
                        shell.zoom(bubble)
                    }
                }
            UndoScope(history: shell.undoManager(for: bubble), content: shell.content(of: bubble))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding([.horizontal, .bottom], 10)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(ShellView.space))
            .onChanged {
                shell.dragBubble(
                    bubble, from: $0.startLocation, by: $0.translation, velocity: $0.velocity,
                    pointer: $0.location)
            }
            .onEnded { shell.endBubbleDrag(pointer: $0.location) }
    }
}
