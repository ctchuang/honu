/// Which edges of a bubble a resize moves: one for an edge, two for a corner.
struct Edges: OptionSet, Hashable {
    let rawValue: Int

    static let left = Edges(rawValue: 1 << 0)
    static let right = Edges(rawValue: 1 << 1)
    static let top = Edges(rawValue: 1 << 2)
    static let bottom = Edges(rawValue: 1 << 3)

    static let topLeft: Edges = [.top, .left]
    static let topRight: Edges = [.top, .right]
    static let bottomLeft: Edges = [.bottom, .left]
    static let bottomRight: Edges = [.bottom, .right]
}
