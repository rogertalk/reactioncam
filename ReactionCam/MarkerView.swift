import UIKit

class MarkerView: UIView, TextureProvider, UITextViewDelegate {

    var orientation: UIDeviceOrientation = .unknown

    override var isHidden: Bool {
        didSet {
            // TODO: Fade out marker before hiding it.
            if self.isHidden {
                self.clear()
            } else {
                self.updateColor(SettingsManager.markerColor)
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .clear

        self.layer.borderWidth = 16

        self.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(MarkerView.handleMarkerPan)))
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(MarkerView.handleTap)))
    }

    func addText() {
        // Add a text field to the marker view.
        let box = self.bounds
        let textView = UITextView(frame: CGRect(x: 30, y: box.height / 2 - 150, width: box.width - 60, height: 100))
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.keyboardAppearance = .dark
        textView.returnKeyType = .done
        textView.font = UIFont.annotationFont(ofSize: 32)
        textView.textAlignment = .left
        textView.textColor = SettingsManager.markerColor
        textView.tintColor = SettingsManager.markerColor
        textView.delegate = self
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(MarkerView.handleTextViewPan)))
        self.addSubview(textView)
        textView.becomeFirstResponder()
    }

    func updateColor(_ color: UIColor) {
        self.borderColor = color.withAlphaComponent(0.2)
    }

    // MARK: - TextureProvider

    func provideTexture(renderer: Composer, forHostTime time: CFTimeInterval) -> MTLTexture? {
        var viewSize = CGSize.zero
        DispatchQueue.main.sync {
            viewSize = self.bounds.size
        }

        var size: CGSize
        var transform = CGAffineTransform(scaleX: 1, y: -1)
        switch orientation {
        case .landscapeLeft:
             size = CGSize(width: viewSize.height, height: viewSize.width)
            transform = transform.rotated(by: -CGFloat.pi / 2)
        case .landscapeRight:
            size = CGSize(width: viewSize.height, height: viewSize.width)
            transform = transform.translatedBy(x: size.width, y: -size.height).rotated(by: CGFloat.pi / 2)
        default:
            size = viewSize
            transform = transform.translatedBy(x: 0, y: -size.height)
        }

        let data = self.getDrawingData()
        guard data.count > 0 else {
            return nil
        }

        let context = CGContext.create(size: size)!
        context.concatenate(transform)

        UIGraphicsPushContext(context)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 5
        shadow.shadowColor = UIColor(white: 0, alpha: 0.6)
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        for item in data {
            switch item {
            case let .shape(path, color):
                context.beginPath()
                context.addPath(path)
                context.setFillColor(color)
                context.fillPath()
            case let .text(frame, text, font, color):
                NSString(string: text).draw(in: frame, withAttributes: [
                    NSAttributedStringKey.font: font,
                    NSAttributedStringKey.shadow: shadow,
                    NSAttributedStringKey.strokeColor: UIColor.white,
                    NSAttributedStringKey.strokeWidth: NSNumber(value: 12),
                    ])
                NSString(string: text).draw(in: frame, withAttributes: [
                    NSAttributedStringKey.font: font,
                    NSAttributedStringKey.foregroundColor: color,
                    ])
            }
        }
        UIGraphicsPopContext()

        return renderer.makeTexture(fromContext: context, pixelFormat: .bgra8Unorm)
    }

    // MARK: - UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text != "\n" else {
            textView.resignFirstResponder()
            return false
        }
        return true
    }

    // MARK: - Private

    private var markerLayer: CAShapeLayer?

    private let path = UIBezierPath()

    private var isEditing: Bool {
        get {
            return self.subviews.contains(where: { $0.isFirstResponder })
        }
    }

    private func clear() {
        self.subviews.forEach {
            ($0 as? UITextView)?.removeFromSuperview()
        }
        self.layer.sublayers?.forEach {
            ($0 as? CAShapeLayer)?.removeFromSuperlayer()
        }
    }

    private enum DrawingData {
        case shape(path: CGPath, color: CGColor)
        case text(frame: CGRect, text: String, font: UIFont, color: UIColor)
    }

    /// Synchronously extract drawing data from main thread (do not call from main thread!)
    private func getDrawingData() -> [DrawingData] {
        var data = [DrawingData]()
        DispatchQueue.main.sync {
            guard let sublayers = self.layer.sublayers else {
                return
            }
            for layer in sublayers {
                guard
                    let shape = layer as? CAShapeLayer,
                    var path = shape.path,
                    let color = shape.strokeColor
                    else { continue }
                if shape.lineCap == kCALineCapRound {
                    path = path.copy(strokingWithWidth: shape.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0)
                }
                data.append(.shape(path: path, color: color))
            }
            for view in self.subviews {
                guard let field = view as? UITextView, let text = field.text else {
                    continue
                }
                data.append(.text(frame: field.frame, text: text, font: field.font!, color: field.textColor!))
            }
        }
        return data
    }

    @objc private dynamic func handleTextViewPan(recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view else {
            return
        }
        let translation = recognizer.translation(in: self)
        view.frame = view.frame.offsetBy(dx: translation.x, dy: translation.y)
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private dynamic func handleMarkerPan(recognizer: UIPanGestureRecognizer) {
        guard !self.isEditing else {
            return
        }
        let p = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            self.path.move(to: p)
            let layer = CAShapeLayer()
            layer.path = self.path.cgPath
            layer.strokeColor = SettingsManager.markerColor.cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = kCALineCapRound
            layer.lineJoin = kCALineJoinRound
            layer.lineWidth = 6
            self.layer.addSublayer(layer)
            self.markerLayer = layer
        case .changed:
            self.path.lineCapStyle = .round
            self.path.addLine(to: p)
            self.markerLayer?.path = self.path.cgPath
        case .cancelled, .ended:
            self.path.removeAllPoints()
            self.markerLayer = nil
        case .failed, .possible:
            break
        }
    }

    @objc private dynamic func handleTap(recognizer: UITapGestureRecognizer) {
        let touch = recognizer.location(ofTouch: 0, in: self)
        let layer = CAShapeLayer()
        layer.path = UIBezierPath(ovalIn: CGRect(x: touch.x, y: touch.y, width: 15, height: 15)).cgPath
        layer.fillColor = SettingsManager.markerColor.cgColor
        layer.strokeColor = SettingsManager.markerColor.cgColor
        self.layer.addSublayer(layer)
    }
}
