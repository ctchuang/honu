import Foundation

extension CGSize {
    static func + (a: CGSize, b: CGSize) -> CGSize {
        CGSize(width: a.width + b.width, height: a.height + b.height)
    }
}
