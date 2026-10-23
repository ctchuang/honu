import Foundation

extension CGRect {
    /// The smallest rectangle around `points`, or the null rectangle if there
    /// are none.
    init(around points: [CGPoint]) {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
        else {
            self = .null
            return
        }
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
