import SwiftUI

/// One bubble in interactive Liquid Glass, tinted the way its microapp says.
/// It shows its title (unless its content shows it) over the content its
/// microapp makes, and dragging moves it.
struct BubbleView: View {
    let bubble: Bubble
    let shell: Shell
    let glass: Namespace.ID
    /// Where bubbles above lie, cut away from this one's glass and content.
    let cuts: [Cut]

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: bubble.cornerRadius, style: .continuous)
    }

    var body: some View {
        let appearance = shell.appearance(of: bubble)
        content(appearance: appearance, title: shell.title(of: bubble))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Content below another bubble is drawn above that bubble's glass,
            // so it is cut away too.
            .clipShape(CutAway(shape: shape, cuts: cuts))
            .contentShape(shape)
            // The glass goes on the content itself, which keeps the content in
            // front of it; a glass layer of its own would be drawn over the
            // content. Only the glass breathes, so the content holds still.
            .glassEffect(
                glassStyle(appearance), in: CutAway(shape: shape, swell: bubble.swell, cuts: cuts)
            )
            .glassEffectID(bubble.id, in: glass)
            .gesture(drag)
    }

    private func glassStyle(_ appearance: Appearance) -> Glass {
        let glass: Glass = appearance.tint.map { .regular.tint($0) } ?? .regular
        return glass.interactive()
    }

    private func content(appearance: Appearance, title: String) -> some View {
        VStack(spacing: 0) {
            // Without a title, a strip of glass is left to drag the bubble by.
            Text(appearance.showsTitle ? title : "")
                .font(.headline)
                .foregroundStyle(appearance.textColor)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: appearance.showsTitle ? 36 : 18)
            UndoScope(history: shell.undoManager(for: bubble), content: shell.content(of: bubble))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding([.horizontal, .bottom], 10)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(ShellView.space))
            .onChanged {
                shell.dragBubble(
                    bubble, by: $0.translation, velocity: $0.velocity, pointer: $0.location)
            }
            .onEnded { shell.endBubbleDrag(pointer: $0.location) }
    }
}
