import UIKit

class TooltipView: UIView {
    convenience init(text: String, centerView: UIView) {
        self.init()

        // Tooltips generally point at visual cues and shouldn't be "seen" by voice over. Instead, use accessibilityHint on relevant elements.
        self.accessibilityElementsHidden = true

        self.centerView = centerView
        self.clipsToBounds = false
        self.shapeLayer.fillColor = UIColor.uiYellow.cgColor

        // The tooltip text.
        self.label = UILabel()
        self.label.font = .systemFont(ofSize: 16, weight: .heavy)
        self.label.textAlignment = .center
        self.label.textColor = .black
        self.addSubview(self.label)
        self.setText(text)

        self.alpha = 0
        self.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
    }

    func bounce() {
        guard self.layer.animation(forKey: "bounce") == nil else {
            return
        }
        let anim = CAKeyframeAnimation()
        anim.keyPath = "transform"
        anim.values = [
            CATransform3DIdentity,
            CATransform3DMakeScale(1, 0.7, 1),
            CATransform3DMakeTranslation(0, -80, 0),
            CATransform3DIdentity,
        ]
        anim.keyTimes = [0, NSNumber(value: 1.0 / 15.0), NSNumber(value: 8.0 / 15.0), 1]
        anim.duration = 1
        anim.repeatCount = .greatestFiniteMagnitude
        anim.timingFunctions = [
            CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut),
            CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut),
            CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn),
            CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut),
        ]
        self.layer.add(anim, forKey: "bounce")
    }

    func setText(_ text: String) {
        self.label.text = text
        self.frame.size = CGSize(width: self.label.intrinsicContentSize.width + 40, height: 40)
        self.label.frame.size = self.frame.size
        self.updatePath()
    }

    func show(temporary: Bool = false) {
        if self.isHidden {
            self.alpha = 0
            self.isHidden = false
        }
        if self.alpha == 1 && self.layer.animation(forKey: "bounce") == nil {
            // Bounce if the tooltip was already fully visible.
            self.pulse()
        }
        UIView.animate(
            withDuration: 0.3,
            animations: { self.alpha = 1 },
            completion: { _ in
                guard temporary else { return }
                UIView.animate(
                    withDuration: 0.3,
                    delay: 2.5,
                    options: [],
                    animations: { self.alpha = 0 })
        })
    }

    func stopBouncing() {
        guard let layer = self.layer.presentation() else {
            self.layer.removeAnimation(forKey: "bounce")
            return
        }
        let anim = CABasicAnimation()
        anim.keyPath = "transform"
        anim.fromValue = layer.transform
        anim.toValue = CATransform3DIdentity
        anim.duration = 0.2
        anim.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
        self.layer.add(anim, forKey: "bounce")
    }

    // MARK: - UIView

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let anchor = CGPoint(x: self.centerView.bounds.midX, y: self.centerView.bounds.minY)
        let point = self.centerView.convert(anchor, to: self.superview)
        // Note: The negative Y offset should be slightly more than the tip height (see updatePath).
        self.center = CGPoint(x: point.x, y: point.y - 16)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.hideAnimated()
        self.stopBouncing()
    }

    // MARK: - Private

    fileprivate func updatePath() {
        let tipRadius = CGFloat(1.5)
        let tipSize = CGSize(width: 14, height: 8)

        // Calculate the three points in the tooltip arrow and round the tip.
        let left = CGPoint(x: self.bounds.midX - tipSize.width / 2, y: self.bounds.maxY),
        tip = CGPoint(x: self.bounds.midX, y: self.bounds.maxY + tipSize.height),
        right = CGPoint(x: self.bounds.midX + tipSize.width / 2, y: self.bounds.maxY)
        let (center, start, end) = roundedCornerWithLinesFrom(right, via: tip, to: left, radius: tipRadius)

        let path = UIBezierPath(roundedRect: self.bounds, cornerRadius: self.bounds.height / 2)
        path.move(to: right)
        path.addArc(withCenter: center, radius: tipRadius, startAngle: start, endAngle: end, clockwise: true)
        path.addLine(to: left)
        path.close()

        self.shapeLayer.path = path.cgPath
    }

    fileprivate var centerView: UIView!
    fileprivate var label: UILabel!
    fileprivate var shapeLayer: CAShapeLayer {
        return self.layer as! CAShapeLayer
    }
}

private func roundedCornerWithLinesFrom(_ from: CGPoint, via: CGPoint, to: CGPoint, radius: CGFloat) -> (center: CGPoint, startAngle: CGFloat, endAngle: CGFloat) {
    let fromAngle = atan2(via.y - from.y, via.x - from.x)
    let toAngle = atan2(to.y - via.y, to.x - via.x)

    let dx1 = -sin(fromAngle) * radius, dy1 = cos(fromAngle) * radius,
    dx2 = -sin(toAngle) * radius, dy2 = cos(toAngle) * radius

    let x1 = from.x + dx1, y1 = from.y + dy1,
    x2 = via.x + dx1, y2 = via.y + dy1,
    x3 = via.x + dx2, y3 = via.y + dy2,
    x4 = to.x + dx2, y4 = to.y + dy2

    let intersectionX = ((x1*y2-y1*x2)*(x3-x4) - (x1-x2)*(x3*y4-y3*x4)) / ((x1-x2)*(y3-y4) - (y1-y2)*(x3-x4))
    let intersectionY = ((x1*y2-y1*x2)*(y3-y4) - (y1-y2)*(x3*y4-y3*x4)) / ((x1-x2)*(y3-y4) - (y1-y2)*(x3-x4))
    let pi2 = CGFloat.pi / 2
    return (CGPoint(x: intersectionX, y: intersectionY), fromAngle - pi2, toAngle - pi2)
}
