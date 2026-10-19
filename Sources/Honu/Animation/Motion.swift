import Foundation

/// A short motion that marks a change in what a bubble is doing.
enum Motion: Equatable, Sendable {
    /// Floats up a little and settles back: something finished.
    case rise
    /// Shakes side to side: something needs the user.
    case wobble

    var seconds: Double {
        switch self {
        case .rise: 1.2
        case .wobble: 0.6
        }
    }

    /// How far the motion moves the bubble `time` seconds in; back to zero by the end.
    func offset(at time: Double) -> CGSize {
        let u = min(max(time / seconds, 0), 1)
        switch self {
        case .rise:
            return CGSize(width: 0, height: -16 * sin(.pi * u))
        case .wobble:
            let shake = sin(2 * .pi * 5 * time)
            return CGSize(width: 8 * shake * (1 - u) * (1 - u), height: 0)
        }
    }
}
