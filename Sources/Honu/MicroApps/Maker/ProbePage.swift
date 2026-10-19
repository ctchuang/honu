/// The prototype's hand-written microapp: it checks what a page can do in a
/// bubble, and logs the keys that reach it, to find where Honu's own
/// keyboard handling gets in the way.
enum ProbePage {
    static let html = """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>Probe</title>
        <script src="https://cdn.jsdelivr.net/npm/lodash@4.17.21/lodash.min.js"></script>
        <style>
          :root { color-scheme: light dark; --bg: #fff; --fg: #222; --dim: #888; --line: #ddd; }
          @media (prefers-color-scheme: dark) { :root { --bg: #1e1e1e; --fg: #eee; --line: #444; } }
          body { margin: 0; padding: 14px; background: var(--bg); color: var(--fg);
                 font: 13px -apple-system, sans-serif; }
          h2 { font-size: 12px; text-transform: uppercase; color: var(--dim); margin: 14px 0 6px; }
          input, textarea, [contenteditable] { width: 100%; box-sizing: border-box; font: inherit;
                 padding: 6px; border: 1px solid var(--line); border-radius: 6px;
                 background: transparent; color: inherit; margin-bottom: 6px; }
          textarea { height: 48px; }
          #checks div, #keys div { font: 12px ui-monospace, monospace; }
          .ok { color: #2a2; } .bad { color: #d33; }
          button { font: inherit; padding: 4px 10px; }
        </style></head><body>
        <h2>Checks</h2><div id="checks"></div>
        <h2>Saved counter</h2>
        <button id="count">Clicked 0 times</button>
        <h2>Typing</h2>
        <input placeholder="input">
        <textarea placeholder="textarea (try ⌘Z, ⌘A, ⌘C, ⌘V)"></textarea>
        <div contenteditable="true">contenteditable</div>
        <h2>Keys the page receives</h2><div id="keys"></div>
        <script>
          const checks = document.getElementById("checks");
          const show = (name, ok, detail) => {
            const line = document.createElement("div");
            line.className = ok ? "ok" : "bad";
            line.textContent = (ok ? "✓ " : "✗ ") + name + (detail ? " — " + detail : "");
            checks.append(line);
          };
          const attempt = async (name, f) => {
            try { const detail = await f(); show(name, true, detail); }
            catch (e) { show(name, false, String(e)); }
          };
          (async () => {
            show("origin", location.protocol === "honu-app:", location.origin);
            show("secure context", window.isSecureContext);
            await attempt("crypto.subtle", async () => typeof crypto.subtle.digest);
            await attempt("CDN script", async () => { if (!window._) throw "lodash missing"; return _.VERSION; });
            await attempt("fetch (CORS)", async () => (await fetch("https://cdn.jsdelivr.net/npm/lodash@4.17.21/package.json")).status);
            await attempt("honu.fetch", async () => (await honu.fetch("https://example.com/")).status);
            const counter = document.getElementById("count");
            let count = (await honu.load())?.count ?? 0;
            const label = () => counter.textContent = "Clicked " + count + " times";
            label();
            counter.onclick = () => { count += 1; label(); honu.save({ count }); };
            show("honu.load", true, "count " + count);
          })();
          const keys = document.getElementById("keys");
          document.addEventListener("keydown", (e) => {
            const mods = (e.metaKey ? "⌘" : "") + (e.ctrlKey ? "⌃" : "") + (e.altKey ? "⌥" : "") + (e.shiftKey ? "⇧" : "");
            const where = document.activeElement?.tagName?.toLowerCase() ?? "?";
            const line = document.createElement("div");
            line.textContent = mods + e.key + "  →  " + where;
            keys.prepend(line);
            while (keys.children.length > 6) keys.lastChild.remove();
          }, true);
        </script>
        </body></html>
        """
}
