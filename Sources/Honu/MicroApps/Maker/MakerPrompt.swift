/// What Claude is asked when it makes, changes, or fixes a microapp.
enum MakerPrompt {
    /// What Claude is told about writing microapps.
    static let system = """
        You write microapps for Honu: small single-page web apps that each run inside a \
        floating panel on the user's Mac desktop.

        Reply with exactly one complete HTML document and nothing else: no explanation \
        and no Markdown fences. Start with <!doctype html> and end with </html>. Put all \
        CSS and JavaScript inline.

        In <head>, include:
        - <title>: a short name for the microapp, one to three words.
        - <meta name="honu-size" content="WIDTHxHEIGHT">: the size of the page in points, \
        between 240x160 and 1000x800. Keep it compact; most microapps fit in 360x480.
        - <meta name="honu-symbol" content="NAME">: an SF Symbols name for the microapp's \
        closed bubble, such as timer, checklist, or function.

        Design: give the page an opaque background that fills it, support light and dark \
        appearance with prefers-color-scheme, use the system font (-apple-system), and \
        leave no margin around the body. It must fit and work at the size declared; only \
        long content should scroll.

        State: the page runs in a WebKit view whose window.honu object is the only \
        storage that lasts. `await honu.load()` returns what was saved last, or null the \
        first time, and `await honu.save(value)` saves any JSON value. Load when the page \
        starts and save after every change the user makes. Do not use localStorage, \
        sessionStorage, cookies, or IndexedDB: the user can open the microapp several \
        times at once, each with its own state in honu, but those would be shared.

        Network: the page may use the internet. Load libraries from a CDN such as \
        https://cdn.jsdelivr.net only when they help. Use only public services that need \
        no key. `fetch` follows CORS; for a service that does not allow it, use \
        `await honu.fetch(url, { method, headers, body })`, which ignores CORS and \
        returns { status, headers, text }.

        `honu.resize(width, height)` changes the size of the page, for content that needs \
        more or less room. Links to other pages open in the user's browser.

        Write it carefully so that it works the first time: no placeholders or TODOs, \
        and handle empty states and errors.
        """

    /// Asks for a new microapp that does what `description` says.
    static func make(_ description: String) -> String {
        """
        Make this microapp:

        \(description)
        """
    }

    /// Asks for `page` changed as `change` says.
    static func change(_ page: String, of description: String?, as change: String) -> String {
        """
        \(context(page, of: description))
        Change it as follows, keeping what it saves compatible with what it saved before:

        \(change)

        Reply with the whole new page.
        """
    }

    /// Asks for `page` with `problems` fixed.
    static func fix(_ page: String, of description: String?, problems: [String]) -> String {
        """
        \(context(page, of: description))
        It reported these errors as it ran:

        \(problems.map { "- " + $0 }.joined(separator: "\n"))

        Fix them, keeping everything else as it is. Reply with the whole new page.
        """
    }

    private static func context(_ page: String, of description: String?) -> String {
        let asked = description.map { "The user asked for this microapp: \($0)\n\n" } ?? ""
        return """
            \(asked)Here is the microapp's page:

            \(page)

            """
    }
}
