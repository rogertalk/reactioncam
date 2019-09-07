import AVFoundation
import UIKit

protocol VideoViewDelegate: class {
    var videoViewControlsFrame: CGRect? { get }
    func videoView(_ view: VideoView, didChangeNaturalSize size: CGSize)
    func videoView(_ view: VideoView, didSeekTo time: CFTimeInterval)
    func videoView(_ view: VideoView, offsetDidChangeTo offset: Double)
    func videoView(_ view: VideoView, requestShowUI: Bool)
    func videoView(_ view: VideoView, shouldStartPlaying url: URL) -> Bool
    func videoViewDidLoad(_ view: VideoView)
    func videoViewDidReachEnd(_ view: VideoView)
    func videoViewDidPause(_ view: VideoView)
    func videoViewDidPlay(_ view: VideoView)
    func videoViewRequestStartPlaying(_ view: VideoView)
}

extension VideoViewDelegate {
    var videoViewControlsFrame: CGRect? {
        return nil
    }

    func videoView(_ view: VideoView, didChangeNaturalSize size: CGSize) { }
    func videoView(_ view: VideoView, didSeekTo time: CFTimeInterval) { }
    func videoView(_ view: VideoView, offsetDidChangeTo offset: Double) { }
    func videoView(_ view: VideoView, requestShowUI: Bool) { }
    func videoView(_ view: VideoView, shouldStartPlaying url: URL) -> Bool { return true }
    func videoViewDidLoad(_ view: VideoView) { }
    func videoViewDidReachEnd(_ view: VideoView) { }
    func videoViewDidPause(_ view: VideoView) { }
    func videoViewDidPlay(_ view: VideoView) { }
    func videoViewRequestStartPlaying(_ view: VideoView) { view.play() }
}

class VideoView: UIView, TextureProvider {
    weak var delegate: VideoViewDelegate?

    let doesProvideTexture: Bool
    private(set) var isPlaying = false
    var shouldHideUI = true

    private(set) static var currentlyPlayingInstance: VideoView? = nil {
        didSet {
            if oldValue != VideoView.currentlyPlayingInstance {
                oldValue?.pause(showUI: false)
            }
        }
    }

    private(set) var naturalSize: CGSize = .zero {
        didSet {
            guard oldValue != self.naturalSize else { return }
            self.delegate?.videoView(self, didChangeNaturalSize: self.naturalSize)
        }
    }

    private(set) var playbackDuration = Double(0)

    var orientation = UIDeviceOrientation.unknown {
        didSet {
            self.updateOrientation()
        }
    }

    private(set) var playerOffset: Double = 0 {
        didSet {
            guard self.playerOffset != oldValue else {
                return
            }
            self.delegate?.videoView(self, offsetDidChangeTo: self.playerOffset)
            if !self.controlsView.isHidden, let duration = self.player.currentItem?.duration {
                let newValue = Float(self.playerOffset / duration.seconds)
                if abs(newValue - self.scrubber.value) > 0.005 {
                    self.scrubber.value = newValue
                }
            }
        }
    }

    var preferredTransform: CGAffineTransform {
        return self.player.currentItem?.asset.tracks(withMediaType: .video).first?.preferredTransform ?? .identity
    }

    var videoDuration: Double? {
        guard let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite else {
            return nil
        }
        return seconds
    }

    init(frame: CGRect, shouldProvideTexture: Bool) {
        self.doesProvideTexture = shouldProvideTexture
        super.init(frame: frame)
        self.initialize()
    }

    deinit {
        self.clearVideo()
        if let observer = self.timeObserver {
            self.player.removeTimeObserver(observer)
            self.timeObserver = nil
        }
    }

    static func pauseAll(showUI: Bool = false) {
        guard let instance = VideoView.currentlyPlayingInstance else {
            return
        }
        instance.pause(showUI: showUI)
        VideoView.currentlyPlayingInstance = nil
    }

    func clearVideo() {
        // Reset video buffer output.
        self.lastTexturePair = nil
        self.naturalSize = .zero
        if let output = self.output {
            if let oldItem = self.player.currentItem {
                oldItem.remove(output)
            }
            self.output = nil
        }

        // Reset UI.
        self.controlsView.isHidden = true
        self.controlsView.transform = .identity
        self.playButton.setTitleWithoutAnimation("play_arrow")
        self.scrubber.value = 0
        self.scrubber.marks = []
        self.spinner.stopAnimating()
        self.hideUITimer?.invalidate()
        self.retryButton.isHidden = true

        // Reset player.
        self.player.pause()
        self.player.currentItem?.asset.cancelLoading()
        self.player.cancelPendingPrerolls()
        self.player.replaceCurrentItem(with: nil)

        // Remove listening for previous player item completing.
        NotificationCenter.default.removeObserver(self)

        // Reset internal state.
        self.currentURL = nil
        self.hasReportedLoadTime = false
        self.isLoading = false
        self.isPlaying = false
        self.observedItem = nil
        self.playbackDuration = 0
        self.playerLoadingStartTime = nil
        self.playerOffset = 0
    }

    func hideUI(delay: Double = 0) {
        guard self.shouldHideUI else {
            return
        }
        self.hideUITimer?.invalidate()
        self.hideUITimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { timer in
            timer.invalidate()
            self.controlsView.hideAnimated()
            if self.isLoading {
                self.showLoadingUI()
            }
            self.delegate?.videoView(self, requestShowUI: false)
        }
    }

    func loadVideo(url: URL, force: Bool = false) {
        guard url != self.currentURL || self.player.currentItem == nil || force else {
            print("Ignoring second load of identical video URL (\(url.absoluteString))")
            return
        }

        self.clearVideo()
        self.currentURL = url
        self.isLoading = true
        self.showLoadingUI()

        if self.doesProvideTexture {
            let attributes: [String: Any] = [
                kCVPixelBufferMetalCompatibilityKey as String: NSNumber(value: true),
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: Int32(kCVPixelFormatType_32BGRA)),
                ]
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
            self.output = output
        }

        let item = AVPlayerItem(url: url)
        self.observedItem = item

        let asset = item.asset
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            DispatchQueue.main.async {
                guard url == self.currentURL else {
                    print("Video URL changed while loading tracks data")
                    return
                }
                var error: NSError?
                guard asset.statusOfValue(forKey: "tracks", error: &error) == .loaded else {
                    NSLog("%@", "WARNING: Failed to load video (\(error?.localizedDescription ?? "unknown error"))")
                    self.handleLoadFailed()
                    return
                }
                self.player.replaceCurrentItem(with: item)
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(VideoView.playerItemDidStall),
                    name: .AVPlayerItemPlaybackStalled,
                    object: self.player.currentItem)
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(VideoView.playerItemDidReachEnd),
                    name: .AVPlayerItemDidPlayToEndTime,
                    object: self.player.currentItem)
            }
        }
    }

    func pause(showUI: Bool = true) {
        if showUI {
            self.showUI()
        }
        guard self.isPlaying else { return }
        self.isPlaying = false
        self.player.pause()
        self.playButton.setTitle("play_arrow", for: .normal)
        self.playbackTimer?.invalidate()
        self.delegate?.videoViewDidPause(self)
    }

    func play() {
        guard
            let url = self.currentURL,
            self.player.rate == 0,
            self.delegate?.videoView(self, shouldStartPlaying: url) != false
            else { return }
        if !self.hasReportedLoadTime && !self.isPlaying {
            // Ignore isLoading state in this case.
            self.playerLoadingStartTime = Date()
        }
        self.hideUI(delay: 5)
        self.isPlaying = true
        VideoView.currentlyPlayingInstance = self
        guard !self.isLoading else {
            self.showLoadingUI()
            return
        }
        if let item = self.player.currentItem, self.playerOffset / item.duration.seconds > 0.99 {
            self.scrubber.value = 0
            self.player.seek(to: CMTime(seconds: 0, preferredTimescale: 1))
        }
        self.player.play()
        self.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard self.player.rate != 0 else {
                return
            }
            self.playbackDuration += 0.2
        }
        self.playButton.setTitle("pause", for: .normal)
        self.delegate?.videoViewDidPlay(self)
    }

    func recapturePlayer() {
        guard let url = self.currentURL else {
            return
        }
        self.playerLoadingStartTime = Date()
        let offset = self.playerOffset
        self.loadVideo(url: url)
        self.seek(to: offset)
    }

    func releasePlayer() {
        self.player.replaceCurrentItem(with: nil)
        self.playerLoadingStartTime = nil
    }

    func seek(to offset: CFTimeInterval) {
        let time = CMTime(seconds: offset, preferredTimescale: 1000)
        self.playerOffset = offset
        self.player.seek(to: time)
        self.delegate?.videoView(self, didSeekTo: offset)
    }

    func setScrubberMarks(to offsets: [CGFloat]) {
        self.scrubber.marks = offsets
    }

    func showUI() {
        if let duration = self.player.currentItem?.duration {
            self.scrubber.value = Float(self.playerOffset / duration.seconds)
        }
        self.controlsView.layer.removeAllAnimations()
        let wasHidden = self.controlsView.isHidden
        self.controlsView.showAnimated()
        if wasHidden {
            self.playButton.pulse()
        }
        self.hideUITimer?.invalidate()
        self.delegate?.videoView(self, requestShowUI: true)
    }

    func skipForward(seconds: Double) {
        let time = self.player.currentTime()
        self.player.seek(to: CMTime(seconds: time.seconds + 10, preferredTimescale: time.timescale))
    }
    
    func updateOrientation() {
        let rotation: CGFloat
        switch self.orientation {
        case .landscapeRight:
            rotation = .pi / -2
        case .landscapeLeft:
            rotation = .pi / 2
        case .unknown:
            if self.naturalSize.isLandscape {
                rotation = .pi / 2
            } else {
                rotation = 0
            }
        default:
            rotation = 0
        }
        let transform = CGAffineTransform(rotationAngle: rotation)
        // Do not animate if the video is always in the same orientation.
        if self.orientation == .unknown || self.isHidden {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.playerLayer.setAffineTransform(transform)
            CATransaction.commit()
            self.controlsView.transform = transform
            self.layoutSubviews()
        } else {
            self.playerLayer.setAffineTransform(transform)
            UIView.animate(withDuration: 0.2) {
                self.controlsView.transform = transform
            }
        }
    }

    // MARK: - UIView

    override init(frame: CGRect) {
        self.doesProvideTexture = false
        super.init(frame: frame)
        self.initialize()
    }

    required init?(coder aDecoder: NSCoder) {
        self.doesProvideTexture = false
        super.init(coder: aDecoder)
        self.initialize()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window == nil {
            self.pause(showUI: false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.retryButton.frame.size = CGSize(width: 80, height: 80)
        self.retryButton.center = self.center

        self.playerLayer.frame = self.bounds
        if let frame = self.delegate?.videoViewControlsFrame {
            self.controlsView.frame = frame
        } else {
            // Default frame
            let t = self.playerLayer.affineTransform()
            self.controlsView.transform = t
            self.controlsView.frame = t == .identity ?
                CGRect(
                    origin: CGPoint(x: self.center.x - 120, y: min(self.center.y + 80, self.bounds.maxY - 60)),
                    size: CGSize(width: 240, height: 60)) :
                CGRect(
                    origin: CGPoint(x: 32, y: self.center.y - 170),
                    size: CGSize(width: 60, height: 340))
        }

        // Layout controls
        self.playButton.frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        let start = 12 + self.playButton.frame.width
        self.scrubber.frame = CGRect(
            x: start,
            y: 0,
            width: self.controlsView.bounds.width - 16 - start,
            height: self.controlsView.bounds.height)
        if self.bounds.width > 150 && self.bounds.height > 150 {
            self.spinner.activityIndicatorViewStyle = .whiteLarge
        } else {
            self.spinner.activityIndicatorViewStyle = .white
        }
        self.spinner.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
    }

    // MARK: - NSObject

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let item = object as? AVPlayerItem, let key = keyPath else {
            return
        }
        
        switch key {
        case #keyPath(AVPlayerItem.loadedTimeRanges):
            let buffered = item.loadedTimeRanges.reduce(0.0, { previous, value in
                let range = value.timeRangeValue
                let max = range.start.seconds + range.duration.seconds
                return previous > max ? previous : max
            })
            let duration = item.duration.seconds
            DispatchQueue.main.async {
                self.scrubber.buffer = duration > 0 ? CGFloat(buffered / duration) : 0
            }
        case #keyPath(AVPlayerItem.status):
            guard !self.didSetupPlayer else {
                return
            }
            self.didSetupPlayer = true
            DispatchQueue.main.async {
                guard item == self.player.currentItem, item.status == .readyToPlay else {
                    if item.status == .failed {
                        self.handleLoadFailed()
                    }
                    return
                }
                if let output = self.output {
                    item.add(output)
                }
                var videoSize = self.playerLayer.videoRect.size
                if let track = item.asset.tracks(withMediaType: .video).first {
                    let size = track.naturalSize.applying(track.preferredTransform)
                    let area = size.width * size.height
                    if area.isNormal && area >= 10000 {
                        videoSize = size
                    }
                }
                // Ensure the dimensions of the video are valid, and not too small
                let area = videoSize.width * videoSize.height
                if !area.isNormal || area < 10000 {
                    videoSize = CGSize(width: 640, height: 360)
                }
                self.naturalSize = videoSize
                self.updateOrientation()
                self.isLoading = false
                self.delegate?.videoViewDidLoad(self)
                self.seek(to: self.playerOffset)
                // don't overwhelm with the full UI when starting playback
                self.delegate?.videoView(self, requestShowUI: true)
                if self.isPlaying {
                    self.play()
                } else {
                    self.player.preroll(atRate: 1)
                    self.spinner.stopAnimating()
                    self.pause(showUI: false)
                }
            }
        default:
            return
        }
    }

    // MARK: - TextureProvider

    func provideTexture(renderer: Composer, forHostTime time: CFTimeInterval) -> MTLTexture? {
        guard let output = self.output else {
            return nil
        }
        let outputItemTime = output.itemTime(forHostTime: time)
        guard outputItemTime.seconds >= 0 else {
            print("Ignoring negative timestamp")
            return self.lastTexturePair?.metal
        }
        guard output.hasNewPixelBuffer(forItemTime: outputItemTime) else {
            return self.lastTexturePair?.metal
        }
        guard let buffer = output.copyPixelBuffer(forItemTime: outputItemTime, itemTimeForDisplay: nil) else {
            NSLog("%@", "WARNING: Failed to copy pixel buffer")
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, [.readOnly])
        defer { CVPixelBufferUnlockBaseAddress(buffer, [.readOnly]) }
        guard let pair = renderer.makeTexture(fromBuffer: buffer, pixelFormat: .bgra8Unorm) else {
            return self.lastTexturePair?.metal
        }
        self.lastTexturePair = pair
        DispatchQueue.main.async {
            self.naturalSize = CGSize(width: pair.metal.width, height: pair.metal.height)
        }
        return pair.metal
    }

    // MARK: - Private

    private let player = AVPlayer()
    private let spinner = UIActivityIndicatorView(activityIndicatorStyle: .white)

    private var controlsView: UIView!
    private var currentURL: URL?
    private var didSetupPlayer = false
    private var hasReportedLoadTime = false
    private var isLoading = false
    private var lastTexturePair: Composer.TexturePair?

    private var observedItem: AVPlayerItem? {
        didSet {
            if let item = oldValue {
                item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
                item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.loadedTimeRanges))
                self.didSetupPlayer = false
            }
            if let item = self.observedItem {
                item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [], context: nil)
                item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.loadedTimeRanges), options: [], context: nil)
            }
        }
    }

    private var output: AVPlayerItemVideoOutput?
    private var playerLayer: AVPlayerLayer!
    private var playerLoadingStartTime: Date?
    private var playButton: UIButton!
    private var playbackTimer: Timer?
    private var retryButton: UIButton!
    private var scrubber: Scrubber!
    private var timeObserver: Any?
    private var wasPlaying = false
    private var hideUITimer: Timer?

    private func initialize() {
        let preview = AVPlayerLayer(player: self.player)
        preview.backgroundColor = UIColor.clear.cgColor
        preview.masksToBounds = false
        preview.videoGravity = .resizeAspect
        preview.frame = self.bounds
        self.layer.addSublayer(preview)
        self.playerLayer = preview

        let retry = UIButton(type: .custom)
        retry.titleLabel?.font = .materialFont(ofSize: 70)
        retry.setTitle("refresh", for: .normal)
        retry.setTitleColor(.white, for: .normal)
        retry.setTitleColor(UIColor.white.withAlphaComponent(0.4), for: .highlighted)
        retry.addTarget(self, action: #selector(VideoView.reload), for: .touchUpInside)
        self.addSubview(retry)
        self.retryButton = retry

        self.controlsView = UIView()
        self.controlsView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.addSubview(self.controlsView)
        self.controlsView.layer.cornerRadius = 8
        self.controlsView.clipsToBounds = true

        let play = UIButton(type: .custom)
        play.autoresizingMask = [.flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin]
        play.clipsToBounds = true
        play.titleLabel?.font = .materialFont(ofSize: 60)
        play.layer.cornerRadius = play.frame.height / 2
        play.setTitle("play_arrow", for: .normal)
        play.setTitleColor(.white, for: .normal)
        play.setTitleColor(UIColor.white, for: .highlighted)
        play.addTarget(self, action: #selector(VideoView.togglePlayback), for: .touchUpInside)
        self.controlsView.addSubview(play)
        self.playButton = play

        let scrubber = Scrubber()
        scrubber.tintColor = .uiYellow
        scrubber.addTarget(self, action: #selector(VideoView.handleScrubberValueChanged), for: .valueChanged)
        scrubber.addTarget(self, action: #selector(VideoView.handleBeginScrubbing), for: .touchDown)
        scrubber.addTarget(self, action: #selector(VideoView.handleEndScrubbing), for: .touchUpInside)
        scrubber.addTarget(self, action: #selector(VideoView.handleEndScrubbing), for: .touchUpOutside)
        scrubber.maximumTrackTintColor = UIColor(white: 1, alpha: 0.4)
        self.controlsView.addSubview(scrubber)
        self.scrubber = scrubber

        self.backgroundColor = .clear
        self.addSubview(self.spinner)

        self.timeObserver = self.player.addPeriodicTimeObserver(forInterval: CMTimeMake(1, 30), queue: DispatchQueue.main) {
            [weak self] time -> Void in
            guard let view = self else { return }
            guard view.playerOffset != time.seconds else {
                if view.playerLoadingStartTime == nil {
                    view.playerLoadingStartTime = Date()
                }
                view.spinner.startAnimating()
                return
            }
            if view.isLoading {
                view.isLoading = false
                view.player.seek(to: CMTime(seconds: view.playerOffset, preferredTimescale: 1000))
            } else {
                view.playerOffset = time.seconds
            }
            if
                let url = view.currentURL,
                !url.isFileURL,
                let stallTime = view.playerLoadingStartTime.flatMap({ Date().timeIntervalSince($0) })
            {
                let videoType = view.doesProvideTexture ? "External" : "Internal"
                let eventName: String
                if !view.hasReportedLoadTime {
                    eventName = "Video View (\(videoType)) Load"
                    view.hasReportedLoadTime = true
                } else {
                    eventName = "Video View (\(videoType)) Stall"
                }
                Logging.debug(eventName, ["TimeToPlay": stallTime])
                view.playerLoadingStartTime = nil
            }
            view.spinner.stopAnimating()
        }
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(VideoView.handleTap)))
    }

    @objc private dynamic func handleScrubberValueChanged(sender: UISlider) {
        guard let item = self.player.currentItem else {
            return
        }
        let duration = item.duration.seconds
        self.player.seek(to: CMTime(seconds: Double(sender.value) * duration, preferredTimescale: 1000))
    }

    @objc private dynamic func handleBeginScrubbing() {
        self.hideUITimer?.invalidate()
        self.player.pause()
    }

    @objc private dynamic func handleEndScrubbing() {
        self.showLoadingUI()
        if self.isPlaying {
            self.play()
        }
    }

    private func handleLoadFailed() {
        self.observedItem = nil
        self.retryButton.isHidden = false
        self.spinner.stopAnimating()
    }

    @objc private dynamic func handleTap() {
        let isShowingUI = !self.controlsView.isHidden
        if isShowingUI {
            self.hideUI()
        } else {
            self.showUI()
            self.hideUI(delay: 5)
        }
        Logging.debug("Video View Action", ["Action": "ToggleUI", "Result": !isShowingUI])
    }
    
    @objc private dynamic func playerItemDidReachEnd() {
        self.isPlaying = false
        self.delegate?.videoViewDidReachEnd(self)
    }

    @objc private dynamic func playerItemDidStall() {
        self.isLoading = true
        self.showLoadingUI()
    }

    @objc private dynamic func reload() {
        guard let url = self.currentURL else {
            return
        }
        self.loadVideo(url: url, force: true)
    }

    private func showLoadingUI() {
        if self.isPlaying && self.playerLoadingStartTime == nil {
            self.playerLoadingStartTime = Date()
        }
        self.spinner.startAnimating()
    }

    @objc private dynamic func togglePlayback() {
        Logging.debug("Video View Action", ["Action": self.isPlaying ? "Pause" : "Play"])
        self.isPlaying ? self.pause() : self.delegate?.videoViewRequestStartPlaying(self) ?? self.play()
    }
}
