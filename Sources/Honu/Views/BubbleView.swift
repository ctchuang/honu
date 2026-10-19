import SwiftUI

/// One bubble in interactive Liquid Glass, tinted the way its microapp says.
/// A closed bubble shows its title (or a symbol), an open one its title over
/// the content its microapp makes. Dragging moves it, and double-clicking
/// opens or closes it.
struct BubbleView: View {
    let bubble: Bubble
    let shell: Shell
    let glass: Namespace.ID

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: bubble.cornerRadius, style: .continuous)
    }

    var body: some View {
        let app = shell.registry.app(bubble.target.app)
        let appearance = app?.appearance(of: bubble.target.item) ?? Appearance()
        let title = shell.registry.title(of: bubble.target)
        content(app: app, appearance: appearance, title: title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(shape)
            // The glass goes on the content itself, which keeps the content in
            // front of it; a glass layer of its own would be drawn over the
            // content. Only the glass breathes, so the content holds still.
            .glassEffect(glassStyle(appearance), in: Swelled(shape: shape, by: bubble.swell))
            .glassEffectID(bubble.id, in: glass)
            .onTapGesture(count: 2) { shell.stage.toggle(bubble) }
            .gesture(drag)
    }

    private func glassStyle(_ appearance: Appearance) -> Glass {
        let glass: Glass = appearance.tint.map { .regular.tint($0) } ?? .regular
        return glass.interactive()
    }

    @ViewBuilder
    private func content(app: (any MicroApp)?, appearance: Appearance, title: String) -> some View {
        if bubble.isOpen {
            VStack(spacing: 0) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appearance.textColor)
                    .lineLimit(1)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                app?.content(of: bubble.target.item, viewState: bubble.viewState)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding([.horizontal, .bottom], 10)
            }
            .transition(.opacity)
        } else if let symbol = appearance.symbol {
            Image(systemName: symbol)
                .font(.system(size: bubble.closedSide * 0.38, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .transition(.opacity)
        } else {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(appearance.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(12)
                .transition(.opacity)
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

/// `shape` grown by `amount` on every side, past the view's own bounds.
private struct Swelled: Shape {
    let shape: RoundedRectangle
    var amount: CGFloat

    init(shape: RoundedRectangle, by amount: CGFloat) {
        self.shape = shape
        self.amount = amount
    }

    func path(in rect: CGRect) -> Path {
        shape.inset(by: -amount).path(in: rect)
    }
}
