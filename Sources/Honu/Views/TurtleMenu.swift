import SwiftUI

/// The turtle's menu, opened where the turtle was clicked: one item per
/// microapp, which starts a new item there, and Exit.
struct TurtleMenu: View {
    let shell: Shell

    static let width: CGFloat = 190
    /// About how tall the menu is, for keeping it on screen.
    static let estimatedHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(shell.menuChoices) { choice in
                MenuItem(label: choice.label) { shell.choose(choice.id) }
            }
            Divider()
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
            MenuItem(label: "Exit") { NSApp.terminate(nil) }
        }
        .padding(6)
        .frame(width: Self.width)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One item of the turtle's menu, highlighted while hovered.
private struct MenuItem: View {
    let label: String
    let action: () -> Void
    // Spelled out instead of `@State`, whose macro ships only with Xcode.
    private let hovered = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            Text(label)
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
