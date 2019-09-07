import UIKit

protocol ActionBarDelegate: class {
    func actionBar(_ actionBar: ActionBar, action: ActionBar.Action, translation: CGPoint, state: UIGestureRecognizerState)
    func actionBar(_ actionBar: ActionBar, requestingAction action: ActionBar.Action)
}

class ActionBar: UIView {
    enum Action: String {
        case back
        case startRecording, stopRecording
        case closeModal, closePop
        case filter
        case finishCreation
        case flashOff, flashOn
        case gradientSlider
        case help
        case igtv
        case markerOn, markerOff
        case options, optionsEnabled
        case portrait, landscape
        case presentImage, clearImage
        case presentWeb, clearWeb
        case requestReaction
        case rotateScreen
        case text
        case useBackCamera, useFrontCamera
        case videoOn, videoOff
    }

    enum Alignment {
        case leading, center, trailing
    }

    enum Axis {
        case horizontal, vertical
    }

    /// The size of the action buttons.
    var buttonSize = CGSize(width: 50, height: 50) {
        didSet { self.layoutSubviews() }
    }

    weak var delegate: ActionBarDelegate?

    /// The actions to show in the action bar.
    var actions = [Action]() {
        didSet {
            self.layoutChange(from: oldValue, to: self.actions)
        }
    }

    var alignment = Alignment.center {
        didSet { self.layoutSubviews() }
    }

    var axis = Axis.horizontal {
        didSet { self.layoutSubviews() }
    }

    var shouldShowButtonBackdrop: Bool = false

    var spacing: CGFloat = 0

    var transformActions = CGAffineTransform(rotationAngle: 0) {
        didSet {
            for button in self.buttons {
                button.transform = self.transformActions
            }
        }
    }

    /// Gets the action represented by the provided button (if it's currently visible).
    func action(for button: ActionButton) -> Action? {
        guard let index = self.buttons.index(of: button) else {
            return nil
        }
        return self.actions[index]
    }

    /// Gets the button that represents the provided action (if it's currently visible).
    func button(for action: Action) -> ActionButton? {
        guard let index = self.actions.index(of: action) else {
            return nil
        }
        return self.buttons[index]
    }

    // MARK: - UIView

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isOpaque = false
        self.layer.rasterizationScale = UIScreen.main.scale
        self.layer.shouldRasterize = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard self.bounds.contains(point) else {
            return false
        }
        return self.subviews.contains {
            let localPoint = CGPoint(x: point.x - $0.frame.origin.x, y: point.y - $0.frame.origin.y)
            return $0.point(inside: localPoint, with: event)
        }
    }

    override func layoutSubviews() {
        self.layoutChange(from: self.actions, to: self.actions)
    }

    // MARK: - Private

    private var buttons = [ActionButton]()

    @objc private dynamic func buttonDragged(gestureRecognizer: UIPanGestureRecognizer) {
        guard let button = gestureRecognizer.view as? ActionButton, let action = self.action(for: button) else {
            return
        }
        self.delegate?.actionBar(self, action: action, translation: gestureRecognizer.translation(in: button), state: gestureRecognizer.state)
    }

    @objc private dynamic func buttonTapped(sender: ActionButton) {
        guard let action = self.action(for: sender) else {
            return
        }
        self.delegate?.actionBar(self, requestingAction: action)
    }

    private func createButton(for action: Action) -> ActionButton {
        // Set a material icon to use. Note that for toggle actions, we set the opposite icon to represent
        // the current state as opposed to the state you will get once you perform the action.

        var backgroundColor: UIColor? = nil
        var buttonForceHideBorder = false
        var buttonBounds = CGRect(origin: .zero, size: self.buttonSize)
        var buttonRadius: CGFloat? = nil
        var icon: String? = nil
        var iconColor = UIColor.white
        var iconImage: UIImage? = nil
        var iconSize = CGFloat(28)
        var labelFrame: CGRect? = nil
        var trackingIdentifier: String? = nil

        switch action {
        case .startRecording, .stopRecording:
            preconditionFailure("Don't use this method for the record button")
        case .back:
            icon = "arrow_back"
            iconColor = .white
            iconSize = 32
        case .clearImage, .clearWeb, .closeModal:
            icon = "close"
            iconSize = 24
        case .closePop:
            icon = "close"
            iconSize = 24
        case .filter:
            icon = "tag_faces"
        case .finishCreation:
            icon = "check"
            iconColor = .black
            iconSize = 32
            backgroundColor = .uiYellow
        case .flashOff:
            icon = "flash_on"
        case .flashOn:
            icon = "flash_off"
        case .igtv:
            buttonForceHideBorder = true
            buttonRadius = 8
            iconImage = #imageLiteral(resourceName: "igtv")
            trackingIdentifier = "igtvHint"
        case .requestReaction:
            icon = "send"
            iconSize = 23
        case .gradientSlider:
            buttonBounds = CGRect(origin: .zero, size: CGSize(width: 24, height: 64))
            buttonRadius = 8
            iconImage = #imageLiteral(resourceName: "gradient")
        case .help:
            icon = "help"
        case .landscape:
            icon = "fullscreen_exit"
        case .markerOff:
            icon = "border_color"
            iconSize = 24
        case .markerOn:
            icon = "mode_edit"
            iconSize = 24
        case .options:
            icon = "more_vert"
        case .optionsEnabled:
            icon = "more_vert"
            iconColor = .uiYellow
        case .presentImage:
            icon = "photo"
        case .portrait:
            icon = "fullscreen"
        case .presentWeb:
            icon = "video_library"
        case .rotateScreen:
            icon = "screen_rotation"
        case .text:
            icon = "format_size"
        case .useBackCamera:
            icon = "camera_front"
        case .useFrontCamera:
            icon = "camera_rear"
        case .videoOff:
            icon = "videocam_off"
        case .videoOn:
            icon = "videocam"
        }

        let button = ActionButton(frame: buttonBounds)
        button.backgroundColor = .clear
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.layer.borderColor = UIColor.white.cgColor
        button.layer.cornerRadius = buttonRadius ?? buttonBounds.width / 2
        if self.shouldShowButtonBackdrop {
            if !buttonForceHideBorder {
                button.layer.borderWidth = 2
            }
            if iconImage == nil {
                button.backgroundColor = UIColor.black.withAlphaComponent(0.25)
            }
        } else {
            button.setHeavyShadow()
        }
        if let backgroundColor = backgroundColor {
            button.backgroundColor = backgroundColor
        }
        if let icon = icon {
            button.titleLabel?.font = UIFont.materialFont(ofSize: iconSize)
            button.setTitle(icon, for: .normal)
            button.setTitleColor(iconColor, for: .normal)
            button.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .highlighted)
        }
        if let iconImage = iconImage {
            button.setImage(iconImage, for: .normal)
            button.imageView?.clipsToBounds = true
            button.imageView?.contentMode = .scaleAspectFill
            button.imageView?.layer.cornerRadius = button.layer.cornerRadius
        }
        if let labelFrame = labelFrame {
            button.overlayLabel.frame = labelFrame
            button.overlayLabel.isHidden = false
        }
        button.updateBadge(identifier: trackingIdentifier)
        return button
    }

    private func layoutCenters(numButtons: Int) -> [CGPoint] {
        let isHorizontal = self.axis == .horizontal
        let size = (isHorizontal ? self.buttonSize.width : self.buttonSize.height) + self.spacing
        // Get the coordinate of the middle of the first button.
        let start: CGFloat
        let totalSpace = isHorizontal ? self.bounds.width : self.bounds.height
        switch self.alignment {
        case .center:
            start = totalSpace / 2 - size * (CGFloat(numButtons) / 2 - 0.5)
        case .trailing:
            start = totalSpace - size * (CGFloat(numButtons) - 0.5) + self.spacing
        case .leading:
            start = size / 2
        }
        return (0..<numButtons).map {
            let origin = start + size * CGFloat($0)
            return isHorizontal ? CGPoint(x: origin, y: self.bounds.midY) : CGPoint(x: self.bounds.midX, y: origin)
        }
    }

    private func layoutChange(from: [Action], to: [Action]) {
        guard from != to else { return }

        // TODO: Make sure there are no duplicates in from/to.
        let oldButtons = self.buttons
        let buttons: [ActionButton] = to.map {
            if let prevIndex = from.index(of: $0) {
                return oldButtons[prevIndex]
            } else {
                return self.createButton(for: $0)
            }
        }

        self.buttons = buttons

        let centers = self.layoutCenters(numButtons: buttons.count)
        for (i, button) in buttons.enumerated() {
            if oldButtons.contains(button) {
                // The button was already there, move it to its new place.
                UIView.animate(withDuration: 0.2) { button.center = centers[i] }
                continue
            }
            // The button was just created, fade it in.
            button.alpha = 0
            self.addSubview(button)
            button.center = centers[i]
            button.addTarget(self, action: #selector(ActionBar.buttonTapped), for: .touchUpInside)
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(ActionBar.buttonDragged))
            button.addGestureRecognizer(recognizer)
            button.transform = self.transformActions
            UIView.animate(withDuration: 0.2) { button.alpha = 1 }
        }

        for button in oldButtons {
            if buttons.contains(button) {
                continue
            }
            // The button was just removed, fade it out.
            button.removeTarget(self, action: #selector(ActionBar.buttonTapped), for: .touchUpInside)
            UIView.animate(
                withDuration: 0.2,
                animations: { button.alpha = 0 },
                completion: { _ in button.removeFromSuperview() })
        }
    }
}
