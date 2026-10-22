import SwiftUI

/// The menu the turtle opens on a right click, for what is rarely needed:
/// whether Honu shows on every desktop, and Exit.
struct SystemMenu: View {
    let shell: Shell

    static let width: CGFloat = 210
    /// About how tall the menu is, for keeping it on screen.
    static let estimatedHeight: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuItem(label: "Show on All Desktops", isChecked: shell.isOnAllDesktops) {
                shell.toggleAllDesktops()
            }
            MenuItem(label: "Exit") { NSApp.terminate(nil) }
        }
        .padding(6)
        .frame(width: Self.width)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Where to put a menu of `size` opened at `point` on a screen of `screen`:
/// its top-left corner at the point, moved back as far as it takes to keep
/// the whole menu on screen.
func menuCorner(of size: CGSize, at point: CGPoint, in screen: CGSize) -> CGPoint {
    // Gap kept between the menu and the edges of the screen.
    let margin: CGFloat = 8
    return CGPoint(
        x: min(point.x, screen.width - size.width - margin),
        y: min(point.y, screen.height - size.height - margin))
}

/// One item of a menu, highlighted while hovered, with a checkmark before it
/// if it is checked. Every item leaves room for one, so labels line up.
struct MenuItem: View {
    let label: String
    var isChecked = false
    let action: () -> Void
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    private let hovered = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)
                    .opacity(isChecked ? 1 : 0)
                Text(label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovered.wrappedValue ? Color.accentColor.opacity(0.35) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered.wrappedValue = $0 }
    }
}
