import UIKit

protocol RecordBarDelegate: class {
    func audioLevel(for recordBar: RecordBar) -> Float
    func recordBar(_ recordBar: RecordBar, action: ActionBar.Action, translation: CGPoint, state: UIGestureRecognizerState)
    func recordBar(_ recordBar: RecordBar, requestingAction action: ActionBar.Action)
    func recordBar(_ recordBar: RecordBar, requestingZoom magnitude: Float)
}

class RecordBar: UIView, ActionBarDelegate, RecordButtonDelegate {
    /// The size of the action buttons.
    let actionButtonSize = CGSize(width: 60, height: 60)
    /// The size of the record button.
    let recordButtonSize = CGSize(width: 80, height: 80)
    /// The time the record button has to be touched before it's considered a long press.
    let longPressThreshold = 0.3
    let recordButton: RecordButton

    var transformActions = CGAffineTransform(rotationAngle: 0) {
        didSet {
            self.before.transformActions = self.transformActions
            self.after.transformActions = self.transformActions
            self.recordButton.timeLabel.transform = self.transformActions
        }
    }

    weak var delegate: RecordBarDelegate?

    /// The actions that appear after the record button.
    let after: ActionBar

    /// The actions that appear before the record button.
    let before: ActionBar

    /// Gets the action represented by the provided button (if it's currently visible).
    func action(for button: ActionButton) -> ActionBar.Action? {
        if let action = self.after.action(for: button) {
            return action
        } else if let action = self.before.action(for: button) {
            return action
        } else {
            return nil
        }
    }

    /// Gets the button that represents the provided action (if it's currently visible).
    func button(for action: ActionBar.Action) -> UIButton? {
        if let button = self.after.button(for: action) {
            return button
        } else if let button = self.before.button(for: action) {
            return button
        } else {
            return nil
        }
    }

    // MARK: - UIView

    override init(frame: CGRect) {
        let actionsWidth = (frame.width - self.recordButtonSize.width) / 2
        let actionBarRect = CGRect(origin: .zero, size: CGSize(width: actionsWidth, height: frame.height))
        self.after = ActionBar(frame: actionBarRect)
        self.before = ActionBar(frame: actionBarRect)
        let record = RecordButton(frame: CGRect(origin: .zero, size: self.recordButtonSize))
        self.recordButton = record
        super.init(frame: frame)
        record.autoresizingMask = [.flexibleBottomMargin, .flexibleTopMargin, .flexibleLeftMargin, .flexibleRightMargin]
        record.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        record.delegate = self
        self.after.delegate = self
        self.before.delegate = self
        self.addSubview(self.before)
        self.addSubview(self.after)
        self.addSubview(record)
        self.isOpaque = false
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
        super.layoutSubviews()
        let recordWidth = self.recordButtonSize.width
        let actionsWidth = (self.bounds.width - recordWidth) / 2
        self.after.frame = CGRect(x: actionsWidth + recordWidth, y: 0, width: actionsWidth, height: self.bounds.height)
        self.before.frame = CGRect(x: 0, y: 0, width: actionsWidth, height: self.bounds.height)
    }

    // MARK: - ActionBarDelegate

    func actionBar(_ actionBar: ActionBar, action: ActionBar.Action, translation: CGPoint, state: UIGestureRecognizerState) {
        self.delegate?.recordBar(self, action: action, translation: translation, state: state)
    }

    func actionBar(_ actionBar: ActionBar, requestingAction action: ActionBar.Action) {
        self.delegate?.recordBar(self, requestingAction: action)
    }

    // MARK: - RecordButtonDelegate

    func audioLevel(for recordButton: RecordButton) -> Float {
        return self.delegate?.audioLevel(for: self) ?? 0
    }

    func recordButton(_ recordButton: RecordButton, requestingState recording: Bool) {
        self.delegate?.recordBar(self, requestingAction: recording ? .startRecording : .stopRecording)
    }

    func recordButton(_ recordButton: RecordButton, requestingZoom magnitude: Float) {
        self.delegate?.recordBar(self, requestingZoom: magnitude)
    }
}
