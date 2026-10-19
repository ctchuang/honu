import SwiftUI

/// What one bubble showing a page keeps for itself: the address being typed.
@Observable
@MainActor
final class AddressDraft: FocusTaking {
    var text = ""
    /// Whether the address field should take the keyboard focus when next shown.
    @ObservationIgnored var focusPending: Bool

    init(focusPending: Bool) {
        self.focusPending = focusPending
    }
}

struct WebContent: View {
    let app: WebApp
    let item: ItemID
    let draft: AddressDraft?
    @FocusState private var focused: Bool

    var body: some View {
        if let url = app.url(of: item) {
            PageView(app: app, item: item, source: PageSource(url))
        } else {
            addressField
        }
    }

    private var addressField: some View {
        let text = Binding(
            get: { draft?.text ?? "" },
            set: { draft?.text = $0 }
        )
        return VStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            TextField("Paste a link, then press Return", text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { app.open(text.wrappedValue, in: item) }
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let draft, draft.focusPending {
                draft.focusPending = false
                focused = true
                placeCursorAtEnd()
            }
        }
    }
}
