import SwiftUI

/// Shows a microapp: a field to describe it, then what Claude writes, then
/// the page running, with a bar below for asking for changes.
struct MakerView: View {
    let app: MakerApp
    let item: ItemID
    let microapp: GeneratedApp
    let state: FocusRequestState
    @FocusState private var focused: Bool

    static let error = Color(red: 0.85, green: 0.3, blue: 0.25)

    var body: some View {
        switch microapp.status {
        case .describing(let error):
            describing(error: error)
        case .writing(.making):
            WritingPreview(text: microapp.written)
        case .writing, .running:
            VStack(spacing: 0) {
                MicroappView(
                    app: app, item: item, folder: microapp.folder.url,
                    version: microapp.version)
                ChangeBar(app: app, item: item, microapp: microapp)
            }
        }
    }

    private func describing(error: String?) -> some View {
        let draft = Binding(get: { microapp.draft }, set: { microapp.draft = $0 })
        return VStack(alignment: .leading, spacing: 8) {
            if let error {
                Text(error).foregroundStyle(Self.error).lineLimit(3)
            }
            TextField(
                "Describe a microapp, such as a pomodoro timer", text: draft, axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .lineLimit(1...4)
            .focused($focused)
            .onSubmit { app.make(item) }
            Text("Press Return, and Claude writes it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .takesFocus(state, requests: microapp.focusRequests, $focused)
    }
}

/// What Claude has written of the page so far, as it streams in.
struct WritingPreview: View {
    let text: String

    /// How much of the end of the page is shown.
    private static let tail = 4000

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(text.isEmpty ? "Thinking…" : "Writing… \(kilobytes(text))")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                Text(verbatim: String(text.suffix(Self.tail)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }
}

/// The bar below a running microapp: a field for asking Claude to change
/// it, a button to fix the errors it reported, and one to undo the last
/// change. While Claude writes, it shows how far it has got.
struct ChangeBar: View {
    let app: MakerApp
    let item: ItemID
    let microapp: GeneratedApp

    static let height: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            if case .writing(let job) = microapp.status {
                ProgressView().controlSize(.small)
                let doing = job == .fixing ? "Fixing" : "Changing"
                Text(
                    microapp.written.isEmpty
                        ? "\(doing)…" : "\(doing)… \(kilobytes(microapp.written))"
                )
                .foregroundStyle(.secondary)
                Spacer()
            } else {
                changeField
                if !microapp.problems.isEmpty {
                    let count = microapp.problems.count
                    Button("Fix", systemImage: "exclamationmark.triangle.fill") { app.fix(item) }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .help(
                            "Ask Claude to fix the \(count == 1 ? "error" : "\(count) errors") "
                                + "it reported:\n" + microapp.problems.joined(separator: "\n"))
                }
                if microapp.canRevert {
                    Button("Undo Change", systemImage: "arrow.uturn.backward") {
                        app.revert(item)
                    }
                    .labelStyle(.iconOnly)
                    .help("Go back to the microapp before the last change")
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(height: Self.height)
    }

    private var changeField: some View {
        let draft = Binding(get: { microapp.draft }, set: { microapp.draft = $0 })
        return VStack(alignment: .leading, spacing: 1) {
            if let notice = microapp.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(MakerView.error)
                    .lineLimit(1)
                    .help(notice)
            }
            TextField("Ask Claude to change it…", text: draft)
                .textFieldStyle(.plain)
                .onSubmit { app.change(item) }
        }
    }
}

/// `text`'s size in kilobytes, as Claude writes it.
private func kilobytes(_ text: String) -> String {
    let size = Double(text.utf8.count) / 1000
    return size < 10 ? String(format: "%.1f KB", size) : "\(Int(size)) KB"
}
