import Foundation

/// Shortens `text` to a bubble label.
func shortLabel(_ text: String) -> String {
    let limit = 24
    guard text.count > limit else { return text }
    let label = text.prefix(limit).trimmingCharacters(in: .whitespaces)
    return label + "…"
}
