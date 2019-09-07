import CoreGraphics

enum PipConfig: Equatable {
    enum Edge {
        case top, right, bottom, left
    }

    case cameraOnly, contentOnly
    case contentAtBottom, contentAtTop
    case cameraFloating(edge: Edge, position: CGFloat)
    case contentFloating(edge: Edge, position: CGFloat)
    case invalid

    var isContentAbove: Bool {
        switch self {
        case .cameraFloating, .cameraOnly:
            return false
        default:
            return true
        }
    }

    func closestConfigFor(camera: CGSize, content: CGSize, in container: CGSize) -> PipConfig {
        guard
            (camera.width >= 1 && camera.height >= 1) || (content.width >= 1 && content.height >= 1),
            container.width >= 1 && container.height >= 1
            else { return .invalid }
        guard camera.width >= 1 && camera.height >= 1 else {
            return .contentOnly
        }
        guard content.width >= 1 && content.height >= 1 else {
            return .cameraOnly
        }
        /// If the content can be flush with the top/bottom and edges of the screen (portrait only).
        let contentCanBeFlush = container.width < container.height && content.width / content.height > 1.5
        switch self {
        case .cameraFloating, .cameraOnly, .contentOnly, .invalid:
            break
        case .contentAtBottom, .contentAtTop:
            if !contentCanBeFlush {
                return .contentFloating(edge: .bottom, position: 1)
            }
        case let .contentFloating(edge, position):
            if contentCanBeFlush {
                switch edge {
                case .top:
                    return .contentAtTop
                case .right where position < 0.5, .left where position < 0.5:
                    return .contentAtTop
                default:
                    return .contentAtBottom
                }
            }
        }
        return self
    }

    func framesFor(camera: CGSize, content: CGSize, in container: CGSize, margin: CGFloat = 10) -> (camera: CGRect, content: CGRect) {
        switch self {
        case let .cameraFloating(edge, position):
            return (
                self.fit(box: camera, along: edge, position: position, of: container, margin: margin),
                CGRect(origin: .zero, size: container)
            )
        case .cameraOnly:
            return (CGRect(origin: .zero, size: container), .zero)
        case .contentAtBottom, .contentAtTop:
            let contentSize = CGSize(width: container.width, height: round(container.width * (content.height / content.width)))
            let cameraSize = CGSize(width: container.width, height: container.height - contentSize.height)
            if case .contentAtBottom = self {
                return (CGRect(origin: .zero, size: cameraSize), CGRect(origin: CGPoint(x: 0, y: cameraSize.height), size: contentSize))
            } else {
                return (CGRect(origin: CGPoint(x: 0, y: contentSize.height), size: cameraSize), CGRect(origin: .zero, size: contentSize))
            }
        case let .contentFloating(edge, position):
            return (
                CGRect(origin: .zero, size: container),
                self.fit(box: content, along: edge, position: position, of: container, margin: margin)
            )
        case .contentOnly:
            return (.zero, CGRect(origin: .zero, size: container))
        case .invalid:
            return (.zero, .zero)
        }
    }

    // - MARK: - Equatable

    static func ==(lhs: PipConfig, rhs: PipConfig) -> Bool {
        switch (lhs, rhs) {
        case (.cameraOnly, .cameraOnly),
             (.contentAtBottom, .contentAtBottom),
             (.contentAtTop, .contentAtTop),
             (.contentOnly, .contentOnly):
            return true
        case let (.cameraFloating(e1, p1), .cameraFloating(e2, p2)),
             let (.contentFloating(e1, p1), .contentFloating(e2, p2)):
            return e1 == e2 && p1 == p2
        default:
            return false
        }
    }

    // - MARK: - Private

    private func fit(box: CGSize, along edge: Edge, position: CGFloat, of container: CGSize, margin: CGFloat) -> CGRect {
        guard container.width >= 1 && container.height >= 1 && box.width >= 1 && box.height >= 1 else {
            return CGRect(x: max(container.width - margin, 0),
                          y: max(container.height - margin, 0),
                          width: 0, height: 0)
        }
        // Resize the box to fit within the current container.
        let ratio = box.width / box.height
        let width, height: CGFloat
        if container.width > container.height {
            if ratio > 1 {
                width = round(container.width / 2.5 - margin * 2)
                height = round(width / ratio)
            } else {
                height = round(container.height / 1.5 - margin * 2)
                width = round(height * ratio)
            }
        } else {
            if ratio > 1 {
                height = round(container.height / 3 - margin * 2)
                width = round(height * ratio)
            } else {
                height = round(container.height / 2.5 - margin * 2)
                width = round(height * ratio)
            }
        }
        // Position the box within the container.
        let x, y: CGFloat
        switch edge {
        case .top, .bottom:
            x = round(margin + (container.width - width - margin * 2) * position)
            y = (edge == .top) ? margin : (container.height - height - margin)
        case .right, .left:
            x = (edge == .right) ? (container.width - width - margin) : margin
            y = round(margin + (container.height - height - margin * 2) * position)
        }
        // Finally, return all the variables as a CGRect.
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
