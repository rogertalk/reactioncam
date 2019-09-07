import AVFoundation
import UIKit

protocol VideoTrimmerDelegate: class {
    func videoTrimmerDidCancel(_ videoTrimmer: VideoTrimmerViewController)
    func videoTrimmer(_ videoTrimmer: VideoTrimmerViewController, didFinishEditing output: AVURLAsset)
}

class VideoTrimmerViewController: UIViewController, AMVideoRangeSliderDelegate {

    let minimumDuration: Double = 5

    weak var delegate: VideoTrimmerDelegate?

    @IBOutlet weak var selectSectionView: UIView!
    @IBOutlet weak var cutView: UIView!
    @IBOutlet weak var finishButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var playerContainer: UIView!
    @IBOutlet weak var rangeSlider: AMVideoRangeSlider!
    @IBOutlet weak var undoButton: UIButton!

    override var prefersStatusBarHidden: Bool {
        return true
    }

    func load(asset: AVURLAsset) {
        self.video = asset
        self.updateSliderConfig()
        NotificationCenter.default.removeObserver(self)
        self.player.pause()
        self.player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(VideoTrimmerViewController.playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: self.player.currentItem)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.rangeSlider.delegate = self
        self.rangeSlider.sliderTintColor = .uiRed
        self.rangeSlider.middleThumbTintColor = .uiYellow
        self.updateSliderConfig()

        self.player.actionAtItemEnd = .pause

        let preview = AVPlayerLayer(player: self.player)
        preview.backgroundColor = UIColor.clear.cgColor
        preview.masksToBounds = false
        preview.videoGravity = .resizeAspect
        self.playerContainer.layer.addSublayer(preview)
        self.playerLayer = preview

        self.timeObserver = self.player.addPeriodicTimeObserver(forInterval: CMTimeMake(1, 60), queue: DispatchQueue.main) {
            [weak self] time -> Void in
            guard
                let vc = self,
                vc.player.rate > 0,
                let duration = vc.player.currentItem?.duration.seconds,
                !duration.isNaN,
                !duration.isZero
                else { return }
            // If the current time stamp is approximately the lower bound of the crop section, skip to the upper bound.
            // TODO: A better check for this
            let upper = vc.rangeSlider.upperValue
            let p = round(time.seconds * 60)
            if vc.isCropping && (p >= round(vc.rangeSlider.lowerValue * duration * 60) && p < floor(upper * duration * 60)) {
                if upper < 1 {
                    vc.seek(to: upper)
                } else {
                    vc.stop()
                }
            } else {
                vc.rangeSlider.middleValue = time.seconds / duration
            }
        }

        self.isCropping = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.playerLayer?.frame = self.playerContainer.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(false)
        self.player.replaceCurrentItem(with: nil)
    }
    
    // MARK: - Actions

    @IBAction func closeTapped(_ sender: Any) {
        Logging.debug("Video Trimmer Action", ["Action": "Close"])
        let alert = UIAlertController(title: "Are you sure? 😲", message: "If you cancel editing, you will lose your edits.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Abandon edits", style: .destructive) { _ in
            Logging.debug("Video Trimmer Action", ["Action": "CloseYes"])
            self.delegate?.videoTrimmerDidCancel(self)
        })
        alert.addCancel() {
            Logging.debug("Video Trimmer Action", ["Action": "CloseCancel"])
        }
        self.present(alert, animated: true)
    }

    @IBAction func doneTapped(_ sender: Any) {
        guard let video = self.video else {
            return
        }
        self.delegate?.videoTrimmer(self, didFinishEditing: video)
        Logging.debug("Video Trimmer Action", ["Action": "Finish"])
    }

    @IBAction func playTapped(_ sender: Any) {
        let isPaused = self.player.rate == 0
        isPaused ? self.play() : self.pause()
        Logging.debug("Video Trimmer Action", ["Action": isPaused ? "Play" : "Pause"])
    }

    @IBAction func selectTapped(_ sender: Any) {
        Logging.debug("Video Trimmer Action", ["Action": "Select"])
        self.pause()
        self.isCropping = !self.isCropping
    }

    @IBAction func deleteTapped(_ sender: Any) {
        Logging.debug("Video Trimmer Action", ["Action": "Delete"])
        guard let duration = self.player.currentItem?.duration,
            (1 - self.rangeSlider.upperValue + self.rangeSlider.lowerValue) * duration.seconds > self.minimumDuration else {
                let alert = UIAlertController(
                    title: "Oops!",
                    message: "The video must be at least \(Int(self.minimumDuration)) seconds long. Select a smaller section to cut out.",
                    preferredStyle: .alert)
                alert.addCancel(title: "Got it")
                self.present(alert, animated: true)
                return
        }

        guard let video = self.video else { return }

        let alert = UIAlertController(
            title: "Delete selection?",
            message: "It will be removed from the video.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Delete", style: .default) { _ in
            // Take first half is from 0 to lower range, and
            // second half from upper range to end of video
            let seconds = duration.seconds
            let timescale = duration.timescale
            let trimPoints = [
                // Lower
                (kCMTimeZero,
                 CMTime(seconds: self.rangeSlider.lowerValue * seconds, preferredTimescale: timescale)),
                // Upper
                (CMTime(seconds: self.rangeSlider.upperValue * seconds, preferredTimescale: timescale),
                 CMTime(seconds: seconds, preferredTimescale: timescale))
            ]

            self.statusIndicatorView.showLoading(title: "Deleting ✂️")
            AssetEditor.trim(asset: video, to: trimPoints) {
                self.statusIndicatorView.showConfirmation()
                guard let asset = $0 else {
                    return
                }
                if let url = self.previousVideoVersion?.url {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch let e {
                        NSLog("WARNING: Could not delete pre-trim video \(e)")
                    }
                }
                self.previousVideoVersion = self.video
                self.load(asset: asset)
                self.isCropping = false
            }
        })
        alert.addCancel(title: "Cancel")
        self.present(alert, animated: true)
    }

    @IBAction func undoTapped(_ sender: Any) {
        guard let previous = self.previousVideoVersion else {
            return
        }

        let alert = UIAlertController(title: "Undo", message: "Are you sure? This will undo your last edit.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Yes", style: .destructive) { _ in
            self.load(asset: previous)
            self.previousVideoVersion = nil
            self.isCropping = false
        })
        alert.addCancel()
        self.present(alert, animated: true)
        Logging.debug("Video Trimmer Action", ["Action": "Undo"])
    }

    // MARK: - AMVideoRangeSliderDelegate

    func rangeSliderLowerThumbValueChanged() {
        self.pause()
        if self.rangeSlider.lowerValue > .leastNonzeroMagnitude {
            self.seek(to: self.rangeSlider.lowerValue)
        } else {
            self.seek(to: self.rangeSlider.upperValue)
        }
    }

    func rangeSliderUpperThumbValueChanged() {
        self.pause()
        if self.rangeSlider.upperValue < 1 {
            self.seek(to: self.rangeSlider.upperValue)
        } else {
            self.seek(to: self.rangeSlider.lowerValue)
        }
    }

    func rangeSliderMiddleThumbValueChanged() {
        self.pause()
        self.seek(to: self.rangeSlider.middleValue)
    }

    // MARK: - Private

    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer?

    private var statusIndicatorView: StatusIndicatorView!
    private var timeObserver: Any?
    private var video: AVURLAsset?

    private var previousVideoVersion: AVURLAsset? {
        didSet {
            self.undoButton.isEnabled = self.previousVideoVersion != nil
        }
    }

    private var isCropping: Bool = false {
        didSet {
            self.rangeSlider.isSelectionEnabled = self.isCropping
            self.selectSectionView.backgroundColor = self.isCropping ? .uiRed : .clear
            self.finishButton.isHidden = self.isCropping
            self.cutView.isHidden = !self.isCropping
        }
    }

    private func pause() {
        self.playButton.setTitle("play_arrow", for: .normal)
        self.player.pause()
    }

    private func play() {
        guard self.player.rate == 0 else {
            return
        }
        self.seek(to: self.rangeSlider.middleValue)
        self.playButton.setTitle("pause", for: .normal)
        self.player.play()
    }

    @objc private dynamic func playerItemDidReachEnd() {
        DispatchQueue.main.async {
            self.stop()
        }
    }

    private func seek(to value: Double) {
        guard let duration = self.player.currentItem?.duration else {
            return
        }
        self.player.seek(
            to: CMTime(seconds: value * duration.seconds,
                       preferredTimescale: 44100),
            toleranceBefore: kCMTimeZero,
            toleranceAfter: kCMTimeZero)
    }

    private func stop() {
        self.pause()
        if self.rangeSlider.lowerValue > .leastNonzeroMagnitude {
            self.rangeSlider.middleValue = 0
        } else {
            self.rangeSlider.middleValue = self.rangeSlider.upperValue
        }
        self.seek(to: self.rangeSlider.middleValue)
    }

    private func updateSliderConfig() {
        guard let asset = self.video, let slider = self.rangeSlider else {
            return
        }
        let duration = asset.duration.seconds
        // Restrict cropping to at least half a second.
        slider.minimumDelta = min(0.5 / duration, 1)
        slider.videoAsset = asset
    }
}
