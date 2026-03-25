import Foundation

extension CGRect {
    func convertedToTopLeading(within containerHeight: CGFloat) -> CGRect {
        CGRect(
            x: minX,
            y: containerHeight - maxY,
            width: width,
            height: height
        ).standardized
    }
}

extension Sequence where Element == CGRect {
    var unionRect: CGRect {
        reduce(CGRect.null) { result, rect in
            result.isNull ? rect : result.union(rect)
        }
    }
}
