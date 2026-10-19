import Foundation

/// Seconds since a fixed moment, the clock that animations, the frame tick,
/// the octopus's memory, and autosave all run on.
@MainActor
func now() -> TimeInterval {
    Date.now.timeIntervalSinceReferenceDate
}
