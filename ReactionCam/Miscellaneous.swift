import ActiveLabel
import UIKit

class AnywhereAlertController: UIAlertController {
    func show() {
        DispatchQueue.main.async {
            let alertWindow = UIWindow(frame: UIScreen.main.bounds)
            alertWindow.rootViewController = UIViewController()
            alertWindow.windowLevel = UIWindowLevelAlert + 1;
            alertWindow.makeKeyAndVisible()
            alertWindow.rootViewController?.present(self, animated: true)
        }
    }
}

class BlurredImageView: UIImageView {
    override func awakeFromNib() {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        self.blurView = view
        view.frame = self.bounds
        self.addSubview(view)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.blurView?.frame = self.bounds
    }

    private var blurView: UIVisualEffectView?
}

class BottomSeparatorView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()

        let bottomBorder = CALayer()
        bottomBorder.frame = CGRect(x: 0, y: self.frame.height, width: self.frame.width, height: 0.5)
        bottomBorder.backgroundColor = UIColor.lightGray.cgColor
        self.layer.addSublayer(bottomBorder)
    }
}

class CameraControlButton: UIButton {
    override func awakeFromNib() {
        super.awakeFromNib()
        self.layer.cornerRadius = self.frame.width / 2
        self.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.shadowOpacity = 0.2
        self.layer.shadowRadius = 1
        self.layer.shadowColor = UIColor.lightGray.cgColor
    }
}

class GradientView: UIView {
    @IBInspectable var bottomAlpha: CGFloat = 0.7
    @IBInspectable var topAlpha: CGFloat = 0.7

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setupGradient()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupGradient()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.gradient.colors = [
            UIColor.black.withAlphaComponent(self.topAlpha).cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(self.bottomAlpha).cgColor,
        ]
        self.gradient.frame = self.bounds
    }

    private let gradient = CAGradientLayer()

    private func setupGradient() {
        self.gradient.locations = [0, 0.20, 0.75, 1]
        self.gradient.startPoint = CGPoint(x: 0.5, y: 0)
        self.gradient.endPoint = CGPoint(x: 0.5, y: 1)
        self.gradient.rasterizationScale = UIScreen.main.scale
        self.gradient.shouldRasterize = true
        self.layer.insertSublayer(self.gradient, at: 0)
    }
}

class BadgeButton: UIButton {
    enum BadgePosition {
        case bottomLeft, bottomRight, topLeft, topRight
    }

    func updateBadge(identifier: String? = nil, position: BadgePosition? = .topLeft) {
        self.badgeTrackingIdentifier = identifier ?? self.badgeTrackingIdentifier
        self.badgePosition = position ?? self.badgePosition
        guard let identifier = self.badgeTrackingIdentifier, SettingsManager.shouldShowNewBadge(for: identifier) else {
            self.newBadge?.isHidden = true
            return
        }
        if let badge = self.newBadge {
            badge.isHidden = false
        } else {
            let origin: CGPoint
            switch self.badgePosition {
            case .topLeft:
                origin = CGPoint(x: 0 - 18, y: -10)
            case .topRight:
                origin = CGPoint(x: self.frame.maxX - 16, y: -10)
            case .bottomLeft:
                origin = CGPoint(x: 0 - 16, y: self.frame.maxY - 20)
            case .bottomRight:
                origin = CGPoint(x: self.frame.maxX - 16, y: self.frame.maxY - 20)
            }
            let badge = UILabel(frame: CGRect(origin: origin, size: CGSize(width: 34, height: 22)))
            badge.clipsToBounds = true
            badge.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
            badge.layer.cornerRadius = 4
            badge.text = "NEW"
            badge.textColor = .white
            badge.textAlignment = .center
            badge.backgroundColor = .red
            badge.isUserInteractionEnabled = false
            badge.isHidden = false
            self.addSubview(badge)
            self.newBadge = badge
        }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if let identifier = self.badgeTrackingIdentifier {
            SettingsManager.reportNewBadgeInteraction(for: identifier)
            self.updateBadge()
        }
    }

    private var badgePosition: BadgePosition = .topLeft
    private var badgeTrackingIdentifier: String? = nil
    private var newBadge: UILabel?
}

class HighlightButton: BadgeButton {
    var isLoading: Bool = false {
        didSet {
            if self.isLoading {
                self.loader.startAnimating()
                self.setTitle(nil, for: .normal)
                self.isUserInteractionEnabled = false
            } else {
                self.loader.stopAnimating()
                self.setTitle(self.title, for: .normal)
                self.isUserInteractionEnabled = true
            }
        }
    }

    override var isEnabled: Bool {
        didSet {
            if self.isEnabled {
                self.backgroundColor = self.buttonColor
                self.layer.borderColor = self.outlineColor?.cgColor
            } else {
                self.backgroundColor = self.highlightedButtonColor
                self.layer.borderColor = self.disabledColor?.cgColor
            }
        }
    }

    override var isHighlighted: Bool {
        didSet {
            if self.isHighlighted {
                self.backgroundColor = self.highlightedButtonColor
                self.layer.borderColor = self.highlightedOutlineColor?.cgColor
            } else {
                self.backgroundColor = self.buttonColor
                self.layer.borderColor = self.outlineColor?.cgColor
            }
        }
    }

    var title: String? {
        didSet {
            self.setTitle(self.title, for: .normal)
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.layer.borderWidth = 2
        self.layer.cornerRadius = self.frame.height / 2

        self.title = self.title(for: .normal)

        self.layoutIfNeeded()

        self.loader = UIActivityIndicatorView(frame: self.bounds)
        self.loader.activityIndicatorViewStyle = .white
        self.loader.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.loader.hidesWhenStopped = true

        self.setColors(button: self.backgroundColor ?? .clear, text: self.titleColor(for: .normal) ?? .black)

        self.addSubview(self.loader)
    }

    func setColors() {
        self.setColors(button: self.buttonColor ?? .clear, text: self.textColor ?? .black)
    }

    func setColors(button: UIColor, text: UIColor) {
        self.buttonColor = button
        self.disabledColor = button.withAlphaComponent(0.6)
        self.highlightedButtonColor = text == .black ? .clear : text
        self.textColor = text

        if button == .black || button == .clear {
            self.outlineColor = text
            self.highlightedOutlineColor = text
        } else {
            self.outlineColor = button
            self.highlightedOutlineColor = button
        }

        self.backgroundColor = self.buttonColor
        self.layer.borderColor = self.outlineColor?.cgColor
        self.loader.color = self.textColor

        self.setTitleColor(self.disabledColor, for: .disabled)
        self.setTitleColor(self.buttonColor == .clear ? .black : self.buttonColor, for: .highlighted)
        self.setTitleColor(self.textColor, for: .normal)
    }

    // MARK: - Private

    private var buttonColor: UIColor?
    private var disabledColor: UIColor?
    private var highlightedButtonColor: UIColor?
    private var highlightedOutlineColor: UIColor?
    private var loader: UIActivityIndicatorView!
    private var outlineColor: UIColor?
    private var textColor: UIColor?
}

class LoaderButton: UIButton {
    let loader = UIActivityIndicatorView()

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.setTitleColor(.clear, for: .disabled)
        self.setTitle(nil, for: .disabled)
        self.layoutIfNeeded()

        self.loader.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        self.loader.frame = self.bounds
        self.loader.hidesWhenStopped = true
        self.addSubview(self.loader)
    }

    var isLoading: Bool = false {
        didSet {
            guard self.isLoading else {
                self.loader.stopAnimating()
                self.isEnabled = true
                return
            }
            self.isEnabled = false
            self.loader.startAnimating()
        }
    }
}

class MaterialView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Drop shadow on the avatar.
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowRadius = 3
        self.layer.shadowOffset = CGSize(width: 0, height: 6)
        self.layer.shadowOpacity = 0.7
    }
}

@IBDesignable
class PaddedTextField: UITextField {
    @IBInspectable var horizontalPadding: CGFloat = 0
    @IBInspectable var verticalPadding: CGFloat = 0

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.insetBy(dx: self.horizontalPadding, dy: self.verticalPadding)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.insetBy(dx: self.horizontalPadding , dy: self.verticalPadding)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.insetBy(dx: self.horizontalPadding, dy: self.verticalPadding)
    }
}

class SeparatorCell: UITableViewCell {
    var separator: CALayer?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        let separator = CALayer()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.15).cgColor
        self.separator = separator
        self.layer.addSublayer(separator)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.separator?.frame = CGRect(x: 16, y: self.frame.height - 1, width: self.frame.width - 32, height: 0.5)
    }
}

class SearchTextField: UITextField {
    private var padding = UIEdgeInsets(top: 0, left: 35, bottom: 0, right: 12)

    override func awakeFromNib() {
        super.awakeFromNib()
        self.layoutIfNeeded()

        let glassLabel = UILabel(frame: CGRect(x: 0, y: 0, width: self.frame.height, height: self.frame.height))
        glassLabel.font = UIFont.systemFont(ofSize: 18)
        glassLabel.text = "🔍"
        glassLabel.textAlignment = .center
        glassLabel.textColor = "797979".hexColor
        self.leftView = glassLabel
        self.leftViewMode = .always

        let clearButton = UIButton(frame: CGRect(x: 0, y: 0, width: self.frame.height, height: self.frame.height))
        clearButton.titleLabel!.font = UIFont.materialFont(ofSize: 24)
        clearButton.setTitle("clear", for: .normal)
        clearButton.setTitleColor("797979".hexColor, for: .normal)
        clearButton.addTarget(self, action: #selector(SearchTextField.clearClicked), for: .touchUpInside)
        clearButton.isHidden = true
        self.clearButtonMode = .never
        self.rightView = clearButton
        self.rightViewMode = .always
        self.rightView?.isHidden = true

        self.addTarget(self, action: #selector(SearchTextField.editingDidBegin), for: .editingDidBegin)
        self.addTarget(self, action: #selector(SearchTextField.editingChanged), for: .editingChanged)
    }

    @objc func clearClicked() {
        guard self.delegate?.textFieldShouldClear?(self) ?? true else {
            return
        }
        self.text = ""
        self.sendActions(for: .editingChanged)
        self.becomeFirstResponder()
    }

    @objc func editingChanged() {
        self.rightView!.isHidden = self.text == nil || self.text == ""
    }

    @objc func editingDidBegin() {
        self.rightView!.isHidden = self.text == nil || self.text == ""
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return UIEdgeInsetsInsetRect(bounds, self.padding)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        return UIEdgeInsetsInsetRect(bounds, self.padding)
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return UIEdgeInsetsInsetRect(bounds, self.padding)
    }
}

extension UISegmentedControl {
    override open func awakeFromNib() {
        super.awakeFromNib()
        self.setTitleTextAttributes(
            [NSAttributedStringKey.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
             NSAttributedStringKey.foregroundColor: UIColor.white.withAlphaComponent(0.4)],
            for: .normal)
        self.setTitleTextAttributes([NSAttributedStringKey.font: UIFont.systemFont(ofSize: 18, weight: .semibold), NSAttributedStringKey.foregroundColor: UIColor.white], for: .selected)
        self.tintColor = UIColor.clear
    }
}

extension UIView {
    func shouldPassThrough(_ point: CGPoint, with event: UIEvent?) -> Bool {
        return self.subviews.contains(where: {
            !$0.isHidden &&
                $0.isUserInteractionEnabled &&
                $0.point(inside: self.convert(point, to: $0), with: event)
        })
    }
}

class PassThroughStackView: UIStackView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return self.shouldPassThrough(point, with: event)
    }
}

class PassThroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return self.shouldPassThrough(point, with: event)
    }
}

class PassThroughTableView: UITableView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return self.indexPathForRow(at: point) != nil
    }
}

class Scrubber: UISlider {
    var marks = [CGFloat]() {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    var buffer: CGFloat = 0 {
        didSet {
            self.setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(Scrubber.handlePan)))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        return CGRect(x: 0, y: bounds.midY - 2, width: bounds.width, height: 4)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        UIColor.white.set()
        let marksPath = UIBezierPath()
        self.marks.forEach { offset in
            let x = (self.bounds.width - 6) * offset + 3
            marksPath.addArc(withCenter:
                CGPoint(x: x, y: self.bounds.midY - 8),
                        radius: 2.5,
                        startAngle: 0,
                        endAngle: .pi * 2,
                        clockwise: true)
        }
        marksPath.fill()

        UIColor.white.withAlphaComponent(0.8).set()
        let bufferPath = UIBezierPath(roundedRect: CGRect(x: 0, y: self.bounds.midY - 2, width: self.bounds.width * self.buffer, height: 4), cornerRadius: 2)
        bufferPath.fill()
    }
    
    @objc dynamic private func handlePan(recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.sendActions(for: .touchDown)
        case .changed:
            self.value = self.value + Float(recognizer.translation(in: self).x / self.bounds.width)
            recognizer.setTranslation(.zero, in: nil)
            self.sendActions(for: .valueChanged)
        case .ended:
            self.sendActions(for: .touchUpInside)
        default:
            return
        }
    }
}

class TagLabel: ActiveLabel {
    static let hashtag = ActiveType.custom(pattern: "#\\w+")
    static let mention = ActiveType.custom(pattern: "(?<!\\w)@[a-zA-Z][a-zA-Z0-9._-]*")

    var relevantUsername: String?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        self.customize { label in
            // #hashtags links.
            label.customColor[TagLabel.hashtag] = .uiYellow
            label.customSelectedColor[TagLabel.hashtag] = UIColor.uiYellow.withAlphaComponent(0.4)
            // @username mentions.
            label.customColor[TagLabel.mention] = .uiYellow
            label.customSelectedColor[TagLabel.mention] = UIColor.uiYellow.withAlphaComponent(0.4)
            // https:// mentions.
            label.URLColor = .uiYellow
            label.URLSelectedColor = UIColor.uiYellow.withAlphaComponent(0.4)
            // Use our custom matchers.
            label.enabledTypes = [TagLabel.hashtag, TagLabel.mention]
            label.handleCustomTap(for: TagLabel.hashtag) { match in
                TabBarController.select(tags: [String(match.dropFirst(1))])
            }
            label.handleCustomTap(for: TagLabel.mention) { match in
                let username = String(match.dropFirst(1))
                Intent.getProfile(identifier: username).perform(BackendClient.api) {
                    guard $0.successful, let data = $0.data else {
                        return
                    }
                    TabBarController.select(account: Profile(data: data))
                }
            }
            label.handleURLTap { url in
                guard Recorder.instance.composer != nil else {
                    UIApplication.shared.open(url, options: [:])
                    return
                }
                let urlString = url.absoluteString.lowercased()
                let prefix = "http://"
                let resolvedURL: URL
                if urlString.hasPrefix(prefix) || urlString.hasPrefix("https://") {
                    resolvedURL = url
                } else if let url = URL(string: prefix + urlString) {
                    resolvedURL = url
                } else {
                    resolvedURL = url
                }
                TabBarController.showCreate(url: resolvedURL, ref: nil, relevantUsername: self.relevantUsername,
                                            source: "TagLabel URL Tap")
            }
        }
    }
}

class ToggleButton: HighlightButton {
    
    var isOn: Bool = false {
        didSet {
            self.backgroundColor = self.isOn ? .white : UIColor.white.withAlphaComponent(0.08)
            self.setTitleColor(self.isOn ? .black : .white, for: .normal)
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.isOn = false
        self.layer.borderWidth = 0
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        self.isOn = !self.isOn
    }
}

