import CoreGraphics

enum ComposerLayout: Equatable {
    case cover(position: CGPoint)
    case fit(position: CGPoint)

    static var coverCenter: ComposerLayout {
        return .cover(position: CGPoint(x: 0.5, y: 0.5))
    }

    static var fitBottomRight: ComposerLayout {
        return .fit(position: CGPoint(x: 1.0, y: 1.0))
    }

    static var fitCenter: ComposerLayout {
        return .fit(position: CGPoint(x: 0.5, y: 0.5))
    }

    static func ==(lhs: ComposerLayout, rhs: ComposerLayout) -> Bool {
        switch (lhs, rhs) {
        case let (.cover(a), .cover(b)), let (.fit(a), .fit(b)):
            return a == b
        default:
            return false
        }
    }
}
