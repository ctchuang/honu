import Foundation
import Observation

/// One microapp Claude writes: what the user asked for, its page in its
/// folder, and Claude at work on it, making it, changing it, or fixing it.
@Observable
@MainActor
final class GeneratedApp {
    /// What Claude is writing the page for.
    enum Job: Equatable {
        /// The first page, from the user's description.
        case making
        /// A new page, from what the user asked to change.
        case changing
        /// A new page, without the errors the page reported.
        case fixing
    }

    enum Status: Equatable {
        /// Waiting for a description, with why the last try failed, if it did.
        case describing(error: String?)
        /// Claude is writing a page.
        case writing(Job)
        /// The page runs.
        case running
    }

    /// How long after a page loads its errors count as the page's own, to be
    /// fixed without asking: later ones may come from what the user did.
    static let fixWindow: TimeInterval = 10
    /// How long to wait for more errors before fixing them.
    static let fixDelay: TimeInterval = 1
    /// The most errors kept.
    static let maxProblems = 20

    let folder: AppFolder
    /// What is being typed: the description, then what to change.
    var draft = ""
    /// What the user asked for first, once asked.
    private(set) var description: String?
    private(set) var status: Status
    /// What the page says about itself.
    private(set) var meta = PageMeta()
    /// The size the page asked for, last with `honu.resize`.
    private(set) var size: CGSize?
    /// Counts the pages written, so views know to load the new one.
    private(set) var version = 0
    /// Claude's answer so far.
    private(set) var written = ""
    /// Why the last change or fix failed, while the page before it runs.
    private(set) var notice: String?
    /// Errors the page reported since it loaded.
    private(set) var problems: [String] = []
    /// Counts the times the user has to type again, so views take the focus.
    private(set) var focusRequests = 0
    /// Whether there is a page before the last change to go back to.
    private(set) var canRevert = false

    @ObservationIgnored private(set) var stream: AnswerStream?
    /// When the page last loaded.
    @ObservationIgnored private var loadedAt: TimeInterval?
    /// When the first error since then came in.
    @ObservationIgnored private var firstProblemAt: TimeInterval?
    /// Whether the page's errors may still be fixed without asking: once
    /// per page made or changed, never for a page that is itself a fix.
    @ObservationIgnored private var mayFix = false
    /// Whether the page was just written, so its bubbles rise once it loads.
    @ObservationIgnored private var isNew = false

    /// A microapp in `folder`, with the page there, if one was written, at
    /// the size it last asked for. A microapp saved while Claude was writing
    /// comes back with why it stopped.
    init(
        folder: AppFolder, description: String? = nil, draft: String = "",
        size: CGSize? = nil, error: String? = nil
    ) {
        self.folder = folder
        self.description = description
        self.draft = draft
        if let page = folder.page() {
            status = .running
            notice = error
            show(page)
            if let size {
                resize(to: size)
            }
        } else {
            status = .describing(error: error)
        }
    }

    var isBusy: Bool {
        if case .writing = status { return true }
        return false
    }

    /// Why Claude stopped, as saved: a page still being written when Honu
    /// quits is saved as interrupted.
    var savedError: String? {
        switch status {
        case .describing(let error): error
        case .writing(.making): "Honu quit before the microapp was finished."
        case .writing: "Honu quit before Claude finished the page."
        case .running: notice
        }
    }

    // MARK: Asking Claude

    /// Has Claude make the microapp the draft describes.
    func make(_ claude: any ClaudeClient) {
        guard case .describing = status else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        description = text
        write(.making, MakerPrompt.make(text), claude)
    }

    /// Has Claude change the page as the draft says.
    func change(_ claude: any ClaudeClient) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == .running, !text.isEmpty, let page = folder.page() else { return }
        write(.changing, MakerPrompt.change(page, of: description, as: text), claude)
    }

    /// Has Claude fix the errors the page reported.
    func fix(_ claude: any ClaudeClient) {
        guard status == .running, !problems.isEmpty, let page = folder.page() else { return }
        write(.fixing, MakerPrompt.fix(page, of: description, problems: problems), claude)
    }

    private func write(_ job: Job, _ prompt: String, _ claude: any ClaudeClient) {
        stream = claude.ask(
            ClaudeRequest(prompt: prompt, systemPrompt: MakerPrompt.system, effort: .medium))
        written = ""
        notice = nil
        status = .writing(job)
    }

    /// Takes in what Claude has written, and fixes errors the page reported
    /// since it loaded if they are due. Reports how writing ended if it just
    /// did; a page written rises only once it loads.
    func poll(_ claude: any ClaudeClient, at time: TimeInterval) -> Outcome? {
        if status == .running, mayFix, let first = firstProblemAt, time - first >= Self.fixDelay {
            mayFix = false
            fix(claude)
            return nil
        }
        guard let stream, case .writing(let job) = status else { return nil }
        let (events, isClosed) = stream.take()
        for event in events {
            switch event {
            case .text(let text):
                written += text
            case .done:
                return finish(job)
            case .failed(let message):
                return fail(message)
            }
        }
        return isClosed ? fail("Claude stopped before the page was finished.") : nil
    }

    /// Keeps the page Claude wrote, if it is a whole one.
    private func finish(_ job: Job) -> Outcome? {
        stream = nil
        guard let page = AppSource.page(from: written) else {
            return fail("Claude's answer wasn't a complete page.")
        }
        do {
            try folder.write(page)
        } catch {
            return fail("The page couldn't be saved: \(error.localizedDescription)")
        }
        written = ""
        if job == .changing {
            draft = ""
        }
        status = .running
        show(page)
        mayFix = job != .fixing
        isNew = true
        return nil
    }

    /// Ends writing with `message`. Without a page yet, the description
    /// can simply be sent again; otherwise the page before keeps running.
    private func fail(_ message: String) -> Outcome {
        stream = nil
        written = ""
        if folder.page() == nil {
            status = .describing(error: message)
            focusRequests += 1
        } else {
            status = .running
            notice = message
        }
        return .needsAttention
    }

    /// Stops Claude, as when the microapp is deleted.
    func cancel() {
        stream?.cancel()
        stream = nil
    }

    // MARK: The page

    /// Goes back to the page before the last change.
    func revert() {
        guard status == .running, (try? folder.revert()) == true, let page = folder.page()
        else { return }
        notice = nil
        mayFix = false
        show(page)
    }

    /// Notes that the page loaded. Returns whether it is new, so its bubbles rise.
    func loaded(at time: TimeInterval) -> Bool {
        loadedAt = time
        defer { isNew = false }
        return isNew
    }

    /// Notes an error the page reported.
    func report(_ problem: String, at time: TimeInterval) {
        guard status == .running, problems.count < Self.maxProblems else { return }
        problems.append(problem)
        // Before it has loaded, the page is still starting.
        if firstProblemAt == nil, time - (loadedAt ?? time) <= Self.fixWindow {
            firstProblemAt = time
        }
    }

    /// Takes the size the page asked for, within limits.
    func resize(to size: CGSize) {
        self.size = AppSource.clamped(size)
    }

    /// Shows `page`: what it says about itself, and a new version to load.
    private func show(_ page: String) {
        meta = AppSource.meta(of: page)
        size = meta.size
        problems = []
        firstProblemAt = nil
        loadedAt = nil
        canRevert = !folder.versions.isEmpty
        version += 1
    }
}
