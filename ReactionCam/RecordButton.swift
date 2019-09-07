import AVFoundation
import UIKit

protocol RecordButtonDelegate: class {
    func audioLevel(for recordButton: RecordButton) -> Float
    func recordButton(_ recordButton: RecordButton, requestingState recording: Bool)
    /// If the user is moving their finger up while long pressing, this will be called
    /// on the delegate. The value will be in the range 0.0-1.0 where 0.0 means no
    /// additional zoom and 1.0 means maximum possible zoom.
    func recordButton(_ recordButton: RecordButton, requestingZoom magnitude: Float)
}

class RecordButton: UIButton {
    enum PreviewBias {
        case start, middle, end
    }

    enum RecordState {
        case idle, paused, recording
    }

    let timeLabel = UILabel()

    var baseDuration = TimeInterval(0) {
        didSet {
            self.updateTime()
        }
    }
    weak var delegate: RecordButtonDelegate?

    override var frame: CGRect {
        get { return super.frame }
        set {
            super.frame = newValue
            self.layer.cornerRadius = self.frame.width / 2
        }
    }

    var isLoading = false {
        didSet {
            if self.isLoading {
                self.timeLabel.alpha = 0.3
                self.spinner.startAnimating()
            } else {
                self.timeLabel.alpha = 1
                self.spinner.stopAnimating()
            }
        }
    }

    private(set) var isLongPressing = false

    var previewBias: PreviewBias = .start {
        didSet {
            self.layoutSubviews()
        }
    }

    var recordingState: RecordState = .idle {
        didSet {
            guard self.recordingState != oldValue else {
                return
            }
            switch self.recordingState {
            case .recording:
                self.handleBeginRecording()
            case .idle:
                self.handleEndRecording()
            case .paused:
                self.handleEndRecording(pause: true)
            }
        }
    }

    override init(frame: CGRect) {
        self.recordingOverlay = CALayer()
        self.recordingOverlay.backgroundColor = UIColor.red.withAlphaComponent(0.2).cgColor
        self.recordingOverlay.isHidden = true

        super.init(frame: frame)
        self.layer.borderWidth = 4
        self.borderColor = .uiYellow
        self.clipsToBounds = true

        self.recordingOverlay.frame = self.bounds
        self.layer.addSublayer(self.recordingOverlay)

        self.timeLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.timeLabel.textColor = .white
        self.timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        self.timeLabel.frame = self.bounds
        self.timeLabel.isHidden = true
        self.timeLabel.textAlignment = .center
        self.timeLabel.setSoftShadow()
        self.addSubview(self.timeLabel)

        self.spinner.frame = self.bounds
        self.addSubview(self.spinner)

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(RecordButton.handleTap)))
    }

    func hookPreview() {
        let layer = Recorder.instance.hookCameraPreview()
        self.layer.insertSublayer(layer, below: self.recordingOverlay)
        self.previewLayer = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        switch self.previewBias {
        case .start:
            self.previewLayer?.frame = self.bounds.insetBy(dx: 0, dy: -25).offsetBy(dx: 0, dy: 25)
        case .middle:
            self.previewLayer?.frame = self.bounds
        case .end:
            self.previewLayer?.frame = self.bounds.insetBy(dx: 0, dy: -25).offsetBy(dx: 0, dy: -25)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private let spinner = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)

    private var durationTimer: Timer?
    private var lastZoom = CGFloat(0)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var recordingOverlay: CALayer
    private var startDate: Date?
    private var touchPoint: CGPoint?

    private func handleBeginRecording() {
        self.borderColor = .red
        self.recordingOverlay.isHidden = false

        self.startDate = Date()
        self.durationTimer?.invalidate()
        self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.updateTime()
        }
        self.updateTime()
        self.timeLabel.textColor = .white
        self.timeLabel.isHidden = false
    }

    private func handleEndRecording(pause: Bool = false) {
        self.borderColor = .uiYellow
        self.isUserInteractionEnabled = true
        self.recordingOverlay.isHidden = true

        UIView.animate(withDuration: 0.2) {
            self.backgroundColor = .clear
        }

        if pause {
            self.timeLabel.textColor = .red
            self.timeLabel.isHidden = false
        } else {
            self.timeLabel.isHidden = true
        }

        self.durationTimer?.invalidate()
        self.durationTimer = nil
        self.startDate = nil
    }

    @objc private dynamic func handleTap() {
        if self.recordingState == .recording {
            self.delegate?.recordButton(self, requestingState: false)
            self.isUserInteractionEnabled = false
        } else {
            self.delegate?.recordButton(self, requestingState: true)
        }
    }

    private func updateTime() {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        let interval = self.baseDuration - (self.startDate?.timeIntervalSinceNow ?? 0)
        guard let time = formatter.string(from: interval) else {
            return
        }
        self.timeLabel.text = time
    }
}
