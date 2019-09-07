import AVFoundation
import CoreMotion
import pop
import Speech
import UIKit
import XLActionController

fileprivate let filters: [Filter] = [
    ("Real Life", "", .arbitrary, [:]),
    ("about that life", "CIHighlightShadowAdjust", .apl1011, [:]),
    ("Gang", "CIPhotoEffectChrome", .apl1011, [:]),
    ("anonymous", "CIPixellate", .apl1011, [
        "inputCenter": CIVector(x: 0, y: 0),
        "inputScale": 100]),
    ("AF", "CIPhotoEffectProcess", .apl1011, [:]),
    ("vintage", "CIPhotoEffectMono", .apl1011, [:]),
    ("LIT", "CIThermal", .apl1011, [:]),
    ("Darkroom", "CIColorMonochrome", .apl1011, [
        "inputColor": CIColor(red: 1, green: 0, blue: 0),
        "inputIntensity": 1]),
]

typealias Filter = (name: String, id: String, minimumProcessor: UIDevice.Processor, values: [String: Any])

class CreationViewController:
    UIViewController,
    ActionBarDelegate,
    PermissionsDelegate,
    PresentationViewDelegate,
    RecordBarDelegate,
    RecordPreviewViewDelegate,
    VideoViewDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    UITextFieldDelegate {

    let content = PendingContent()

    var clipboardURL: URL? = nil

    var contentFrame: CGRect {
        var frame = UIScreen.main.bounds
        frame.origin.y += 40
        frame.size.height -= 40
        return frame
    }

    private(set) var isPresenting = false
    var mode: SelectionMode = .react

    override var prefersStatusBarHidden: Bool {
        return true
    }

    var quality: MediaWriterSettings.Quality = .medium
    var requesterUsername: String?

    override var shouldAutorotate: Bool {
        return Recorder.instance.state != .recording
    }

    var source = "Unknown"

    // MARK: - Outlets

    @IBOutlet weak var closeFilters: UIButton!
    @IBOutlet weak var countdownContainerView: UIView!
    @IBOutlet weak var countdownView: UIView!
    @IBOutlet weak var countdownLabel: UILabel!
    @IBOutlet weak var filterSelectionContainer: UIView!
    @IBOutlet weak var filterLabel: UILabel!
    @IBOutlet weak var frontBlixtView: PassThroughView!
    @IBOutlet weak var landscapeTitleLabel: UILabel!
    @IBOutlet weak var navigationHeaderView: UIView!
    @IBOutlet weak var rotationAlertContainerView: UIView!
    @IBOutlet weak var rotationAlertView: UIView!
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var searchHeaderView: UIView!
    @IBOutlet weak var searchTextField: SearchTextField!
    @IBOutlet weak var sendRequestButton: HighlightButton!
    @IBOutlet weak var soundAlertLabel: UILabel!
    @IBOutlet weak var soundAlertView: UIView!
    @IBOutlet weak var titleButton: UIButton!
    @IBOutlet weak var tutorialView: UIView!
    @IBOutlet weak var tutorialDoneButton: HighlightButton!

    func present(url: URL, ref: ContentRef? = nil) {
        guard self.loadDidRun else {
            self.pendingPresentationInfo = (url, ref)
            return
        }
        if let ref = ref {
            self.addRelatedContentEntry(ref: ref)
        }
        if SettingsManager.isVideo(url: url) {
            self.showVideoView()
            self.videoView.loadVideo(url: url)
            self.videoView.showUI()
        } else if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            self.presentationView.attachment = .document(url)
            self.showPresentation()
        } else {
            self.presentationView.attachment = .webPage(url)
            self.showPresentation()
        }
    }

    // MARK: - UIViewController

    override func viewDidAppear(_ animated: Bool) {
        Logging.debug("Creation Appeared", ["DiskSpace": FileManager.default.freeDiskSpace ?? -1])
        super.viewDidAppear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false

        if case .request = self.mode {
            // Content requests don't perform any recording.
            return
        }

        let recorder = Recorder.instance
        guard recorder.composer != nil else {
            Logging.warning("Device Too Old Dialog")
            let alert = UIAlertController(
                title: "Sorry... 😢",
                message: "Unfortunately your \(UIDevice.current.modelName) does not support screen recording.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Help", style: .cancel, handler: { _ in
                Logging.log("Device Too Old Dialog Choice", ["Choice": "Help"])
                HelpViewController.showHelp(presenter: self)
            }))
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                Logging.log("Device Too Old Dialog Choice", ["Choice": "OK"])
                self.dismiss()
            }))
            self.present(alert, animated: true)
            return
        }

        guard PermissionsView.hasPermissions else {
            self.showPermissionsView()
            return
        }

        self.tooltipView.setText("Tap to \(self.isRecordingSession ? "record more" : "record")")
        self.tooltipView.show()

        // Show low disk space warning if needed.
        let settings = MediaWriterSettings(
            quality: self.quality,
            orientation: recorder.orientation.isPortrait ? .portrait : .landscape)
        if let diskSpace = FileManager.default.freeDiskSpace,
            let audioBitrate = (settings.audioSettings[AVEncoderBitRatePerChannelKey] as? NSNumber)?.int64Value,
            let videoBitrate = ((settings.videoSettings[AVVideoCompressionPropertiesKey] as? [String: Any])?[AVVideoAverageBitRateKey] as? NSNumber)?.int64Value {
            // Possible recording time
            let minutes = diskSpace / ((audioBitrate + videoBitrate) / 8) / 60
            if minutes < 10 {
                let alert = UIAlertController(title: "Low space 😬", message: "You only have enough space for \(minutes) minutes of video. Try freeing up some space.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
            }
        }

        self.updateComposerFrames()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppDelegate.applicationActiveStateChanged.removeListener(self)
        Recorder.instance.recorderUnavailable.removeListener(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.tooltipView.setNeedsLayout()
        if self.videoView.isHidden {
            self.markerView.frame = self.contentFrame
            self.presentationView.frame = self.contentFrame
        } else {
            self.markerView.frame = UIScreen.main.bounds
            self.videoView.frame = UIScreen.main.bounds
        }
        self.updateComposerFrames()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.searchTextField.delegate = self
        self.searchView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(CreationViewController.searchViewTapped)))

        if let requestTitleLabel = self.sendRequestButton.titleLabel {
            // Proper size reduction/truncation of text
            requestTitleLabel.adjustsFontSizeToFitWidth = true
            requestTitleLabel.minimumScaleFactor = 0.85
            requestTitleLabel.allowsDefaultTighteningForTruncation = true
            requestTitleLabel.lineBreakMode = .byTruncatingTail
        }

        // Set up the record bar that contains all the actions at the bottom of the screen.
        self.recordBar = RecordBar(frame: CGRect(x: 0, y: self.view.bounds.height - 100, width: self.view.bounds.width, height: 100))
        self.recordBar.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
        self.recordBar.delegate = self

        self.recordPreviewView = RecordPreviewView(frame: CGRect(x: self.view.bounds.width - 10, y: 44, width: 0, height: 0))
        self.recordPreviewView.delegate = self
        self.recordPreviewView.isHidden = true

        self.tooltipView = TooltipView(text: "", centerView: self.recordBar.recordButton)

        // Set up a secondary bar for additional actions at the top of the screen.
        self.topLeftBar = ActionBar(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        self.topLeftBar.alignment = .leading
        self.topLeftBar.buttonSize = CGSize(width: 40, height: 40)
        self.topLeftBar.delegate = self
        self.navigationHeaderView.addSubview(self.topLeftBar)

        // Set up a third bar for additional actions at the top of the screen.
        self.topRightBar = ActionBar(frame: CGRect(x: self.view.bounds.width - 100, y: 0, width: 100, height: 40))
        self.topRightBar.alignment = .trailing
        self.topRightBar.buttonSize = CGSize(width: 40, height: 40)
        self.topRightBar.delegate = self
        self.navigationHeaderView.addSubview(self.topRightBar)

        let actionBarHeight: CGFloat = 50 * 5 + 12 * 4
        self.rightBar = ActionBar(frame: CGRect(x: self.view.bounds.width - 58, y: self.view.bounds.height / 2 - actionBarHeight / 2, width: 50, height: actionBarHeight))
        self.rightBar.axis = .vertical
        self.rightBar.alignment = .center
        self.rightBar.delegate = self
        self.rightBar.shouldShowButtonBackdrop = true
        self.rightBar.spacing = 12
        self.view.addSubview(self.rightBar)

        self.markerView.isHidden = true
        self.presentationView.isHidden = true
        self.videoView.isHidden = true

        // Handle requests for playing video.
        self.presentationView.delegate = self
        self.videoView.delegate = self
        self.videoView.shouldHideUI = false

        let cameraPreviewContainer = UIView(frame: self.view.bounds)
        cameraPreviewContainer.backgroundColor = .clear
        cameraPreviewContainer.isUserInteractionEnabled = false
        self.cameraPreviewContainer = cameraPreviewContainer
        
        // Order all the views correctly in the hierarchy.
        // TODO: Make this cleaner.
        self.view.insertSubview(self.presentationView, at: 0)
        self.view.insertSubview(self.videoView, at: 1)
        self.view.insertSubview(self.cameraPreviewContainer, at: 2)
        self.view.insertSubview(self.markerView, at: 3)
        self.view.insertSubview(self.recordPreviewView, at: 4)
        self.view.insertSubview(self.recordBar, at: 5)
        self.view.insertSubview(self.tooltipView, at: 6)
        self.view.insertSubview(self.soundAlertView, at: 7)
        self.view.insertSubview(self.sendRequestButton, at: 8)
        self.view.insertSubview(self.rightBar, at: 9)
        self.view.insertSubview(self.landscapeTitleLabel, at: 10)
        self.view.insertSubview(self.navigationHeaderView, at: 11)

        self.tutorialView.isHidden = true

        self.loadDidRun = true
        if let (url, ref) = self.pendingPresentationInfo {
            // Prefer front cam for reactions
            // TODO: Decide on whether we want to keep this persist logic around
            SettingsManager.preferFrontCamera = true
            self.pendingPresentationInfo = nil
            self.present(url: url, ref: ref)
        } else {
            self.content.type = .recording(isVlog: true)
        }

        if let composer = Recorder.instance.composer {
            // Set up the camera layer that renders the camera input for the output video.
            let texture = CameraTexture()
            self.cameraLayer = ComposerLayer("Camera", frame: .zero, provider: texture)
            self.cameraTexture = texture

            let preview = CameraPreview(frame: self.view.bounds, composer: composer, texture: texture)
            preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            preview.isPaused = true
            cameraPreviewContainer.addSubview(preview)
            self.filteredCameraPreview = preview

            if self.availableFilters.count > 1 {
                let preview = CameraPreview(frame: self.filterSelectionContainer.bounds, composer: composer, texture: texture)
                preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                preview.isPaused = true
                self.filterSelectionContainer.insertSubview(preview, at: 0)
                self.filterSelectionPreview = preview
            }

            let presentation = ComposerLayer("Presentation (UI)", frame: .zero, provider: UIViewTexture(view: self.presentationView))
            presentation.isOpaque = true
            self.presentationLayer = presentation

            let video = ComposerLayer("Video", frame: .zero, provider: self.videoView)
            video.layout = .fitCenter
            self.videoLayer = video

            let marker = ComposerLayer("Marker", frame: .zero, provider: self.markerView)
            marker.isHidden = true
            self.markerLayer = marker
        }
        self.setWatermark()

        self.uiOrientation = .portrait

        if case let .request(account) = self.mode {
            self.recordBar.isHidden = true
            self.sendRequestButton.isHidden = false
            if let account = account {
                self.sendRequestButton.setTitle("REQUEST @\(account.username)", for: .normal)
            } else {
                self.sendRequestButton.setTitle("REQUEST REACTIONS", for: .normal)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.showSoundAlerts = !self.isCameraOnly

        self.refresh()
        self.refreshActions()
        self.setupMotionManager()
        self.showRecorderPreview()
        self.updateSoundAlert()
        self.updateFlash()

        AppDelegate.applicationActiveStateChanged.addListener(self, method: CreationViewController.handleApplicationActiveStateChanged)
        BackendClient.api.sessionChanged.addListener(self, method: CreationViewController.handleSessionChanged)
        Recorder.instance.faceDetected.addListener(self, method: CreationViewController.handleFaceDetected)
        Recorder.instance.recorderUnavailable.addListener(self, method: CreationViewController.handleRecorderUnavailable)

        NotificationCenter.default.addObserver(self, selector: #selector(CreationViewController.updateHeadphonesAlert), name: .AVAudioSessionRouteChange, object: nil)
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: [], context: nil)

        self.screenBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = CGFloat(1.0)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume" else {
            return
        }
        DispatchQueue.main.async {
            self.updateSoundAlert()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.motionManager.stopAccelerometerUpdates()
        AppDelegate.applicationActiveStateChanged.removeListener(self)
        BackendClient.api.sessionChanged.removeListener(self)
        Recorder.instance.faceDetected.removeListener(self)
        Recorder.instance.recorderUnavailable.removeListener(self)

        NotificationCenter.default.removeObserver(self)
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume", context: nil)

        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true

        switch Recorder.instance.state {
        case .previewing:
            Recorder.instance.stopPreviewing()
        case .recording:
            Logging.danger("Internal State Error", ["Cause": "Left CreationViewController while recording"])
            NSLog("%@", "WARNING: Left CreationViewController while recording")
            self.stopRecording(cancel: true)
            Recorder.instance.stopPreviewing()
        default:
            break
        }

        self.disableFlash()
        if let screenBrightness = self.screenBrightness {
            UIScreen.main.brightness = screenBrightness
        }
    }

    // MARK: - Actions

    @IBAction func nextFilterTapped(_ sender: UIButton) {
        self.incrementFilterIndex(by: 1)
    }

    @IBAction func closeFiltersTapped(_ sender: Any) {
        let filter = self.availableFilters[self.previewFilterIndex]
        Logging.log("Close Filters", ["Selected Filter": filter.name])
        // Revert to previous filter
        self.selectFilter(filterIndex: self.selectedFilterIndex)
        self.previewFilterIndex = self.selectedFilterIndex
        self.filterSelectionPreview?.isPaused = true
        self.filterSelectionContainer.isHidden = true
        self.showRecorderPreview()
        self.refreshActions()
    }

    @IBAction func closeSoundAlertTapped(_ sender: Any) {
        Logging.debug("Camera View Action", [
            "Action": "Close Sound Alert",
            "RecordedSegments": self.content.assets.count,
            "Recording": Recorder.instance.state == .recording])
        self.soundAlertView.hideAnimated()
        self.showSoundAlerts = false
    }

    @IBAction func closeTutorialTapped(_ sender: Any) {
        Logging.debug("Camera View Action", [
            "Action": "Close Tutorial Tapped"])
        self.tutorialView.hideAnimated()
    }

    @IBAction func previousFilterTapped(_ sender: UIButton) {
        self.incrementFilterIndex(by: -1)
    }

    @objc private dynamic func searchViewTapped() {
        Logging.debug("Camera View Action", ["Action": "Search View Dismissed"])
        self.searchTextField.resignFirstResponder()
        self.searchView.hideAnimated()
    }

    @IBAction func sendRequestTapped(_ sender: Any) {
        guard
            case let .request(account) = self.mode,
            let ref = self.relatedContentEntries.last?.ref
            else { return }

        Logging.log("Send Request Tapped", ["Source": self.source])

        guard let recipient = account else {
            self.shareReactionRequest()
            return
        }
        self.statusIndicatorView.showLoading(title: "Sending")
        self.view.isUserInteractionEnabled = false
        Intent.createContentRequest(identifier: String(recipient.id), relatedContent: ref).perform(BackendClient.api) {
            guard $0.successful else {
                self.view.isUserInteractionEnabled = true
                self.statusIndicatorView.hide()
                let alert = UIAlertController(title: "Oops!", message: "Something went wrong. Please try again later.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            self.statusIndicatorView.showConfirmation(title: "Sent!") {
                self.view.isUserInteractionEnabled = true
                // Go back to the user's profile.
                if let vc = self.navigationController?.viewControllers.first(where: { $0 is ProfileViewController }) {
                    self.navigationController?.popToViewControllerModal(vc)
                } else {
                    self.navigationController?.popViewControllerModal()
                }
            }
        }
    }

    @IBAction func titleTapped(_ sender: Any) {
        Logging.debug("Camera View Action", ["Action": "Title Tapped"])
        if let url = self.pageInfo?.pageURL {
            self.searchTextField.text = url.absoluteString
        }
        self.searchHeaderView.setSoftShadow()
        self.searchView.showAnimated()
        self.searchTextField.becomeFirstResponder()
    }

    @IBAction func useFilterTapped(_ sender: HighlightButton) {
        let filter = self.availableFilters[self.previewFilterIndex]
        Logging.log("Use Filter", ["Filter": filter.name])
        self.selectedFilterIndex = self.previewFilterIndex
        self.filterSelectionPreview?.isPaused = true
        self.filterSelectionContainer.isHidden = true
        self.showRecorderPreview()
        self.refreshActions()
    }

    // MARK: - ActionBarDelegate

    func actionBar(_ actionBar: ActionBar, requestingAction action: ActionBar.Action) {
        self.handleAction(action)
    }

    func actionBar(_ actionBar: ActionBar, action: ActionBar.Action, translation: CGPoint, state: UIGestureRecognizerState) {
        switch action {
        case .gradientSlider, .markerOff:
            let x = (SettingsManager.markerHue - Float(translation.y / 1.5)).truncatingRemainder(dividingBy: 360)
            let hue = x < 0 ? x + 360 : x
            if state == .ended {
                SettingsManager.markerHue = hue
            }
            let color = UIColor(hue: CGFloat(hue / 360), saturation: 1, brightness: 1, alpha: 1)
            if let button = actionBar.button(for: .markerOff) {
                button.backgroundColor = color
            }
            self.markerView.updateColor(color)
        default:
            return
        }
    }

    // MARK: - PresentationViewDelegate

    func presentationView(_ view: PresentationView, didChangeTitle title: String) {
        guard let oldInfo = self.pageInfo else {
            return
        }
        self.pageInfo = PageInfo(
            frame: oldInfo.frame,
            pageThumbURL: oldInfo.pageThumbURL,
            pageTitle: title,
            pageURL: oldInfo.pageURL,
            mediaId: oldInfo.mediaId,
            mediaURL: oldInfo.mediaURL)
    }

    func presentationView(_ view: PresentationView, didLoadContent info: PageInfo) {
        self.pageInfo = info
    }

    func presentationView(_ view: PresentationView, requestingToPlay mediaURL: URL, with info: PageInfo) {
        self.pageInfo = info
        self.showVideoView()
        self.videoView.loadVideo(url: mediaURL)
        if Recorder.instance.state == .recording {
            self.videoView.play()
        } else {
            self.videoView.showUI()
        }
        self.refresh()
    }

    func presentationViewRequestingToRecord(_ view: PresentationView) {
        self.startRecording()
    }

    func presentationView(_ view: PresentationView, willLoadContent info: PageInfo) {
        self.pageInfo = info
    }

    // MARK: - RecordBarDelegate

    func audioLevel(for recordBar: RecordBar) -> Float {
        let level = Recorder.instance.audioLevel
        return 1 + 0.1 * level / pow(level, 0.7)
    }

    func recordBar(_ recordBar: RecordBar, action: ActionBar.Action, translation: CGPoint, state: UIGestureRecognizerState) {
    }

    func recordBar(_ recordBar: RecordBar, requestingAction action: ActionBar.Action) {
        self.handleAction(action)
    }

    func recordBar(_ recordBar: RecordBar, requestingZoom magnitude: Float) {
        Recorder.instance.zoom(to: CGFloat(1 + magnitude * 14))
    }

    // MARK: - PermissionDelegate

    func didReceivePermissions() {
        if let view = self.permissionsView {
            self.permissionsView = nil
            UIView.animate(withDuration: 0.3, animations: { view.alpha = 0 }) { _ in
                self.topRightBar.isHidden = false
                self.titleButton.isHidden = false
                view.removeFromSuperview()
            }
        }
        self.showTutorial()
        self.showRecorderPreview()
        self.tooltipView.setText("Tap to record")
        self.tooltipView.show()
    }

    // MARK: - RecordPreviewViewDelegate

    func recordPreviewViewWasTapped(_ view: RecordPreviewView) {
        let configs: [(String, PipConfig)]
        if self.uiOrientation == .portrait {
            configs = [
                // Use bottom right config here so it translates nicely to landscape.
                ("Video in bottom", .contentFloating(edge: .bottom, position: 1)),
                ("Camera in bottom corner", .cameraFloating(edge: .bottom, position: 1)),
            ]
        } else {
            configs = [
                ("Video in bottom corner", .contentFloating(edge: .bottom, position: 1)),
                ("Video in bottom center", .contentFloating(edge: .bottom, position: 0.5)),
                ("Camera in bottom corner", .cameraFloating(edge: .bottom, position: 1)),
            ]
        }
        let sheet = ActionSheetController(title: "Change Layout")
        for (label, config) in configs {
            sheet.addAction(Action(self.pipConfig == config ? "✅ \(label)" : label, style: .default) { _ in
                self.pipConfig = config
                Logging.log("Creation Preview Options", [
                    "Action": "Set Position",
                    "Config": String(describing: config)])
            })
        }
        if !self.isRecordingSession {
            sheet.addAction(Action("Rotate video", style: .default) { _ in
                Logging.log("Creation Preview Options", [
                    "Action": "Rotate",
                    "Config": String(describing: self.pipConfig)])
                self.uiOrientation = self.uiOrientation == .portrait ? .landscapeLeft : .portrait
            })
        }
        sheet.addCancel {
            Logging.log("Creation Preview Options", ["Action": "Cancel"])
        }
        sheet.configurePopover(sourceView: view)
        self.present(sheet, animated: true)
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        // Picker is always portrait, so laying out views before it is disimissed causes bugs in landscape mode.
        picker.dismiss(animated: true) {
            guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
                return
            }
            self.presentationView.attachment = .image(image)
            self.showPresentation()
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Auto-select everything in the web page alert box text field.
        textField.selectAll(nil)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        Logging.debug("Camera View Action", ["Action": "Search/Web", "Input": text])
        self.searchTextField.resignFirstResponder()
        self.searchView.hideAnimated()
        if let url = text.searchURL() {
            self.present(url: url)
            self.hideVideoView()
            self.showPresentation()
            self.showRecorderPreview()
        }
        return false
    }

    // MARK: - VideoViewDelegate

    func videoView(_ view: VideoView, didChangeNaturalSize size: CGSize) {
        self.updateComposerFrames()
    }

    func videoView(_ view: VideoView, didSeekTo time: CFTimeInterval) {
        guard let id = self.pageInfo?.mediaId else { return }
        self.presentationView.notifyMediaScript(id: id, type: "seeked")
    }

    func videoViewDidLoad(_ view: VideoView) {
        self.addRelatedContentEntryFromPageInfo()
        if case .react = self.mode, Recorder.instance.state != .recording {
            self.tooltipView.setText("Tap to \(self.isRecordingSession ? "record more" : "record")")
            self.tooltipView.show()
        }
    }

    func videoViewDidPause(_ view: VideoView) {
        self.refreshActions()
        self.tooltipView.stopBouncing()
        if Recorder.instance.state == .recording {
            self.tooltipView.setText("Tap to pause recording")
            self.tooltipView.show(temporary: true)
        } else {
            self.tooltipView.hideAnimated()
        }
        guard let id = self.pageInfo?.mediaId else { return }
        self.presentationView.notifyMediaScript(id: id, type: "pause")
    }

    func videoViewDidPlay(_ view: VideoView) {
        if let id = self.pageInfo?.mediaId {
            self.presentationView.notifyMediaScript(id: id, type: "play")
        }
        self.addRelatedContentEntryFromPageInfo()
        self.startRecording()
    }

    func videoViewDidReachEnd(_ view: VideoView) {
        if let duration = view.videoDuration, duration < 20 {
            // Auto-loop short content.
            view.play()
            return
        }
        view.pause(showUI: self.markerView.isHidden)
        if Recorder.instance.state == .recording {
            self.tooltipView.setText("Tap to pause recording")
            self.tooltipView.show()
        }
        guard let id = self.pageInfo?.mediaId else { return }
        self.presentationView.notifyMediaScript(id: id, type: "ended")
    }

    func videoViewRequestStartPlaying(_ view: VideoView) {
        var isRequest = false
        if case .request = self.mode {
            isRequest = true
        }
        if self.isRecording || isRequest {
            view.play()
        } else {
            self.startPlaybackOnRecord = true
            self.startRecording()
        }
    }
    
    // MARK: - Private

    private func disableFlash() {
        self.videoView.backgroundColor = .black
        Recorder.instance.toggleTorch(on: false)
        self.frontBlixtView.isHidden = true
    }

    private var lastVisibleRelatedContentEntry: RelatedContentEntry? {
        return self.relatedContentEntries.lazy.reversed().first(where: { $0.visibleInRecording })
    }

    private var maxVolume: Float {
        switch UIDevice.current.modelName {
        case "iPhone 7", "iPhone 7 Plus", "iPhone 8", "iPhone 8 Plus", "iPhone X":
            return 0.5
        default:
            return 0.8
        }
    }

    private var pipConfig: PipConfig = .contentFloating(edge: .bottom, position: 1) {
        didSet {
            self.updateComposerFrames()
        }
    }

    private var uiOrientation: UIDeviceOrientation = .unknown {
        didSet {
            Recorder.instance.orientation = self.uiOrientation
            self.markerView.orientation = self.uiOrientation
            self.videoView.orientation = self.uiOrientation

            let filterBounds = self.filterSelectionContainer.bounds
            let filterInverseBounds = CGRect(x: 0, y: 0, width: filterBounds.height, height: filterBounds.width)

            let cameraBounds = self.view.bounds
            let cameraInverseBounds = CGRect(x: 0, y: 0, width: cameraBounds.height, height: cameraBounds.width)

            let rotation: CGFloat
            switch self.uiOrientation {
            case .landscapeLeft:
                rotation = .pi / 2
                self.filteredCameraPreview?.bounds = cameraInverseBounds
                self.filterSelectionPreview?.bounds = filterInverseBounds
                self.recordBar.recordButton.previewBias = .end
            case .landscapeRight:
                rotation = .pi / -2
                self.filteredCameraPreview?.bounds = cameraInverseBounds
                self.recordBar.recordButton.previewBias = .start
            default:
                rotation = 0
                self.filteredCameraPreview?.bounds = cameraBounds
                self.filterSelectionPreview?.bounds = filterBounds
                self.recordBar.recordButton.previewBias = .start
            }

            var transform = CGAffineTransform(rotationAngle: rotation)
            self.presentationView.bounds = self.contentFrame.applying(transform)
            UIView.animate(withDuration: 0.2) {
                self.updateTitleLabel()
                self.landscapeTitleLabel.transform = transform
                self.countdownView.transform = transform
                self.presentationView.transform = transform
                self.recordBar.transformActions = transform
                self.soundAlertView.transform = transform
                self.rightBar.transformActions = transform
            }
            if Recorder.instance.configuration == .frontCamera {
                transform = transform.scaledBy(x: -1, y: 1)
            }
            self.filterSelectionPreview?.layer.setAffineTransform(transform)
            self.filterSelectionPreview?.frame = filterBounds
            self.filteredCameraPreview?.layer.setAffineTransform(transform)
            self.filteredCameraPreview?.frame = cameraBounds
            self.updateComposerFrames()
            self.refreshActions()
        }
    }

    private let deviceQueue = OperationQueue()
    private let motionManager = CMMotionManager()

    private let availableFilters = filters.filter { UIDevice.current.processor >= $0.minimumProcessor }
    private let markerView = MarkerView(frame: .zero)
    private let presentationView = PresentationView(frame: .zero)
    private let videoView = VideoView(frame: .zero, shouldProvideTexture: true)

    private var brandImageLayer: ComposerLayer?
    private var cameraLayer: ComposerLayer?
    private var cameraPreviewContainer: UIView!
    private var cameraTexture: CameraTexture?
    private var deviceOrientation: UIDeviceOrientation = .unknown
    private var pageInfo: PageInfo? {
        didSet {
            self.addRelatedContentEntryFromPageInfo()
        }
    }

    private var faceCount: Double = 0
    private var faceCountMax: Double = 0
    private var facesCountBeforeFriendsPrimer: Int = 0
    private var filteredCameraPreview: CameraPreview?
    private var filterSelectionPreview: CameraPreview?
    private var isMergingAssets = false
    private var isRecording = false
    private var loadDidRun = false
    private var pendingPresentationInfo: (URL, ContentRef?)?
    private var permissionsView: PermissionsView?
    private var presentationLayer: ComposerLayer?
    private var previousPinchScale = CGFloat(1)
    private var recordBar: RecordBar!
    private var recordPreviewView: RecordPreviewView!
    private var relatedContentEntries = [RelatedContentEntry]()
    private var rightBar: ActionBar!
    private var selectedFilterIndex: Int = 0
    private var screenBrightness: CGFloat?
    private var showSoundAlerts = true
    private var startPlaybackOnRecord = false
    private var statusIndicatorView: StatusIndicatorView!
    private var previewFilterIndex = 0
    private var topLeftBar: ActionBar!
    private var topRightBar: ActionBar!
    private var tooltipView: TooltipView!
    private var markerLayer: ComposerLayer?
    private var videoLayer: ComposerLayer?
    private var usernameLayer: ComposerLayer?

    private var flash: Bool = false {
        didSet {
            self.updateFlash()
        }
    }

    private var isCameraOnly: Bool {
        return self.presentationView.isHidden && self.videoView.isHidden
    }

    private var isRecordingSession: Bool {
        return self.isRecording || !self.content.assets.isEmpty
    }

    private var wasPushedModalStyle: Bool {
        guard let navigation = self.navigationController else {
            return false
        }
        let count = navigation.viewControllers.count
        guard count >= 2 else {
            return false
        }
        return !(navigation.viewControllers[count - 2] is PickSourceViewController)
    }

    private func addRelatedContentEntry(ref: ContentRef) {
        var entry = RelatedContentEntry(ref: ref)
        if let existingIndex = self.relatedContentEntries.index(of: entry) {
            // Remove entry so we can put it back at the end of the list.
            entry = self.relatedContentEntries.remove(at: existingIndex)
            entry.ref = ref
            if self.isRecording {
                entry.visibleInRecording = true
            }
        } else {
            entry.visibleInRecording = self.isRecording
            entry.lookUp() {
                self.refresh()
                self.refreshActions()
            }
        }
        self.relatedContentEntries.append(entry)
        self.refresh()
        self.refreshActions()
    }

    private func addRelatedContentEntryFromPageInfo() {
        guard let info = self.pageInfo, let ref = self.makeContentRef(from: info) else {
            return
        }
        self.addRelatedContentEntry(ref: ref)
    }

    private func countDown(callback: @escaping () -> ()) {
        self.facesCountBeforeFriendsPrimer = Int(round(self.faceCount))
        self.self.tooltipView.hideAnimated()
        self.countdownContainerView.isHidden = false
        self.countdownLabel.text = "3"
        self.countdownLabel.setSoftShadow()
        self.countdownLabel.pulse()
        var time = 3
        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            guard time > 1 else {
                $0.invalidate()
                DispatchQueue.main.async {
                    let faceCount = Int(round(self.faceCount))
                    Logging.log("Creation View Countdown Complete", [
                        "Face Count Before": self.facesCountBeforeFriendsPrimer,
                        "Face Count After": Int(round(self.faceCount)),
                        "Face Count Change": String(format: "%+d", faceCount - self.facesCountBeforeFriendsPrimer)
                        ])
                    self.countdownContainerView.hideAnimated() {
                        callback()
                    }
                }
                return
            }
            time -= 1
            DispatchQueue.main.async {
                self.countdownLabel.text = String(time)
                self.countdownLabel.pulse()
            }
        }
    }

    private func dismiss() {
        let pop = {
            if self.wasPushedModalStyle {
                self.navigationController?.popViewControllerModal()
            } else {
                self.navigationController?.popViewController(animated: true)
            }
            AppDelegate.notifyIfSquelched()
        }

        guard case .react = self.mode, Recorder.instance.composer != nil else {
            pop()
            return
        }

        guard !self.content.isSaved else {
            pop()
            return
        }

        let alert = UIAlertController(
            title: "Delete Recording? 😱",
            message: "You will lose any recorded video from this session.",
            preferredStyle: .alert)

        let continueReaction = UIAlertAction(title: "Continue Recording", style: .default) { _ in
            Logging.debug("Delete Reaction Alert", ["Action": "No", "RecordedSegments": self.content.assets.count])
        }
        let saveReaction = UIAlertAction(title: "Save to Camera Roll", style: .default) { _ in
            Logging.debug("Delete Reaction Alert", ["Action": "Save to Camera Roll", "RecordedSegments": self.content.assets.count])
            self.save(source: "Creation Back") {
                guard $0 != nil else {
                    let alert = UIAlertController(title: "Oops! 😅", message: "Your video was not saved, try to free up some space.", preferredStyle: .alert)
                    alert.addCancel(title: "OK", handler: nil)
                    self.present(alert, animated: true)
                    return
                }
                self.content.discard()
                pop()
            }
        }
        let deleteReaction = UIAlertAction(title: "Delete", style: .destructive) { _ in
            Logging.debug("Delete Reaction Alert", ["Action": "Yes", "RecordedSegments": self.content.assets.count])
            self.content.discard()
            pop()
        }
        if self.isRecordingSession {
            let duration = self.content.duration
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            if let string = formatter.string(from: ceil(duration)) {
                alert.message = "You will lose \(string) of recorded video if you choose to delete."
            }
            alert.addAction(continueReaction)
            alert.addAction(saveReaction)
            alert.addAction(deleteReaction)
            alert.preferredAction = continueReaction
            self.present(alert, animated: true)
        } else {
            self.content.discard()
            pop()
        }
    }

    private func enterAudioMode() {
        Recorder.instance.configuration = .audioOnly
    }

    private func enterVideoMode() {
        Recorder.instance.configuration = SettingsManager.preferFrontCamera ? .frontCamera : .backCamera
    }

    private func goToReview() {
        UIApplication.shared.isIdleTimerDisabled = false
        TabBarController.instance?.showReview(content: self.content, source: self.source)
    }

    private func handleAction(_ action: ActionBar.Action) {
        Logging.debug("Camera View Action", [
            "Action": action.rawValue,
            "RecordedSegments": self.content.assets.count,
            "Recording": Recorder.instance.state == .recording])
        switch action {
        case .back:
            self.videoView.isHidden ? self.presentationView.goBack() : self.hideVideoView()
            if case .react = self.mode, Recorder.instance.state != .recording {
                self.tooltipView.setText("Tap to \(self.isRecordingSession ? "record more" : "record")")
                self.tooltipView.show()
            }
        case .startRecording:
            self.startRecording()
        case .closeModal, .closePop:
            guard self.videoView.isHidden else {
                self.hideVideoView()
                if case .react = self.mode, Recorder.instance.state != .recording {
                    self.tooltipView.setText("Tap to \(self.isRecordingSession ? "record more" : "record")")
                    self.tooltipView.show()
                }
                break
            }
            self.dismiss()
        case .clearImage, .clearWeb:
            self.hidePresentation()
        case .stopRecording:
            self.stopRecording()
        case .filter:
            guard let preview = self.filterSelectionPreview, self.filterSelectionContainer.isHidden else {
                break
            }
            self.videoView.pause()
            preview.isPaused = false
            self.filterSelectionContainer.isHidden = false
        case .finishCreation:
            self.goToReview()
        case .flashOff:
            self.flash = false
        case .flashOn:
            self.flash = true
        case .igtv:
            let alert = UIAlertController(
                title: "Tips for IGTV",
                message: "Upload your reaction to your Instagram TV channel while IGTV is new to go viral! To make a video for IGTV:\n\n📱 Make sure to record VERTICAL video\n\n⏱ Make your video less than 10 minutes long\n\n🖼 Save to Photos after recording",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Get the IGTV app", style: .default) { _ in
                let url = URL(string: "https://itunes.apple.com/us/app/igtv/id1394351700?mt=8")!
                UIApplication.shared.open(url)
            })
            alert.addCancel(title: "Got it!")
            self.present(alert, animated: true)
        case .gradientSlider, .help:
            // Currently not in use.
            break
        case .markerOn:
            self.markerView.isHidden = false
            self.markerLayer?.isHidden = false
            self.videoView.pause()
            self.videoView.hideUI()
        case .markerOff:
            self.markerView.isHidden = true
            self.markerLayer?.isHidden = true
            self.videoView.showUI()
        case .options, .optionsEnabled:
            self.showOptions()
        case .presentImage:
            self.presentationView.attachment = .none
            // TODO: Custom picker.
            let picker = UIImagePickerController()
            picker.delegate = self
            self.present(picker, animated: true)
        case .presentWeb:
            // Clipboard link (except reaction.cam links).
            // TODO: Attempt to prefetch clipboard somewhere to avoid lag?
            if let url = UIPasteboard.general.url, url.host != "www.reaction.cam" {
                self.clipboardURL = url
            }
            self.showWebPageSheet()
        case .requestReaction:
            self.shareReactionRequest()
        case .rotateScreen, .portrait, .landscape:
            if self.isRecordingSession {
                self.showOrientationError(duration: 0.8)
            } else {
                self.uiOrientation = self.uiOrientation == .portrait ? .landscapeLeft : .portrait
            }
        case .text:
            // Ensure that marker mode is on.
            self.markerView.isHidden = false
            self.refreshActions()
            self.markerView.addText()
        case .useFrontCamera, .useBackCamera:
            self.flash = false
            Recorder.instance.switchCamera()
            // TODO: Better way of refreshing camera preview transform
            let current = self.uiOrientation
            self.uiOrientation = current
        case .videoOff:
            self.enterAudioMode()
        case .videoOn:
            self.enterVideoMode()
        }
        self.refreshActions()
    }

    private func makeContentRef(from pageInfo: PageInfo) -> ContentRef? {
        let title = pageInfo.cleanTitle
        guard !title.isEmpty, var url = pageInfo.pageURL else {
            return nil
        }
        if let path = Bundle.main.resourcePath, url.path.hasPrefix(path) {
            url = URL(fileURLWithPath: "/ReactionCam.app" + url.path.dropFirst(path.count),
                      isDirectory: url.hasDirectoryPath)
        }
        return .metadata(
            creator: "TODO",
            url: url,
            duration: Int((self.videoView.videoDuration ?? 0) * 1000),
            title: title,
            videoURL: pageInfo.mediaURL,
            thumbURL: pageInfo.pageThumbURL)
    }

    private func refresh() {
        self.updateTitleLabel()

        if let entry = self.relatedContentEntries.last {
            if let url = entry.content?.thumbnailURL {
                self.recordPreviewView.contentImageURL = url
            } else if case let .metadata(_, _, _, _, _, .some(url)) = entry.ref {
                self.recordPreviewView.contentImageURL = url
            } else {
                self.recordPreviewView.contentImageURL = nil
            }
        } else {
            self.recordPreviewView.contentImageURL = nil
        }

        guard PermissionsView.hasPermissions else {
            return
        }

        if Recorder.instance.configuration == .audioOnly {
            self.enterAudioMode()
        } else {
            self.enterVideoMode()
        }
    }

    private func refreshActions() {
        if self.markerView.isHidden {
            var beforeActions: [ActionBar.Action] = []
            switch self.presentationView.attachment {
            case .webPage:
                if self.videoView.isHidden && self.presentationView.canGoBack {
                    beforeActions.append(.back)
                }
            case .image:
                beforeActions.append(.clearImage)
            default:
                break
            }
            self.recordBar.before.actions = beforeActions
            var rightActions: [ActionBar.Action] = []
            if case .react = self.mode {
                rightActions = []
                if self.isCameraOnly {
                    rightActions.append(Recorder.instance.configuration == .backCamera ? .useFrontCamera : .useBackCamera)
                }
                rightActions.append(self.flash ? .flashOff : .flashOn)
                if self.availableFilters.count > 1, !self.isRecording {
                    rightActions.append(.filter)
                }
                rightActions.append(.markerOn)
                if !self.isRecording && self.content.duration == 0 {
                    rightActions.append(.igtv)
                }
            }
            self.rightBar.actions = rightActions
        } else {
            self.recordBar.before.actions = []
            self.rightBar.actions = [.markerOff, .gradientSlider]
        }

        if self.isRecording {
            self.topRightBar.actions = []
            self.recordBar.after.actions =  []
            if !self.videoView.isHidden {
                self.recordBar.after.actions = []
                self.topLeftBar.actions = self.presentationView.canGoBack  ? [.closeModal] : []
            } else {
                self.topLeftBar.actions = []
            }
        } else {
            self.recordBar.after.actions = self.isRecordingSession && !self.isMergingAssets ? [.finishCreation] : []
            if case .react = self.mode, let content = self.relatedContentEntries.last?.content, !self.isRecordingSession {
                self.topRightBar.actions = [.options]
                if content.relatedCount > 0 {
                    self.topRightBar.actions = [.optionsEnabled]
                } else {
                    self.topRightBar.actions = [.options]
                }
            } else {
                self.topRightBar.actions = []
            }
            switch self.presentationView.attachment {
            case .webPage:
                // Hide the close button if a video view is open (but only if there's a back button!)
                self.topLeftBar.actions = [!self.videoView.isHidden || self.wasPushedModalStyle ? .closeModal : .closePop]
            default:
                // Always let user close video (which will close entire creation view).
                self.topLeftBar.actions = [self.wasPushedModalStyle ? .closeModal : .closePop]
            }
        }

        if let button = self.rightBar.button(for: .markerOff) {
            button.backgroundColor = SettingsManager.markerColor
        }

        if let button = self.rightBar.button(for: .filter) {
            button.backgroundColor = self.previewFilterIndex != 0 ? .uiBlue : UIColor.black.withAlphaComponent(0.25)
        }
    }

    private func setWatermark() {
        guard let composer = Recorder.instance.composer else {
            return
        }
        // Only create brand layers if we haven't done so previously.
        if
            self.brandImageLayer == nil,
            let brandImageProvider = composer.makeProvider(with: #imageLiteral(resourceName: "watermark"))
        {
            self.brandImageLayer = ComposerLayer("Brand", frame: .zero, provider: brandImageProvider)
        }

        if
            let session = BackendClient.api.session,
            let watermark = session.properties["watermark"] as? String ?? (session.hasBeenOnboarded ? "@\(session.username)" : nil),
            !watermark.isEmpty,
            let usernameProvider = composer.makeProvider(with: watermark, font: .fredokaOneFont(ofSize: 66))
        {
            self.usernameLayer = ComposerLayer("Username", frame: .zero, provider: usernameProvider)

        }
        self.updateComposerFrames()
    }

    private func setupMotionManager() {
        self.motionManager.deviceMotionUpdateInterval = 0.3
        guard self.motionManager.isAccelerometerAvailable else {
            return
        }
        self.motionManager.startAccelerometerUpdates(to: self.deviceQueue) { data, error in
            guard error == nil, let acceleration = data?.acceleration else {
                return
            }
            guard acceleration.z > -0.5 && acceleration.z < 0.5 else {
                return
            }
            let new: UIDeviceOrientation
            let difference = abs(acceleration.y) - abs(acceleration.x)
            if difference < -0.25 {
                new = acceleration.x > 0 ? .landscapeRight : .landscapeLeft
            } else if difference > 0.25 {
                new = acceleration.y > 0 ? .portraitUpsideDown : .portrait
            } else {
                return
            }
            DispatchQueue.main.async {
                guard self.deviceOrientation != new else {
                    return
                }
                self.deviceOrientation = new
                guard !self.isRecordingSession else {
                    switch new {
                    case self.uiOrientation, .unknown, .faceUp, .faceDown:
                        self.hideOrientationError(delay: 0.6)
                    default:
                        self.showOrientationError()
                    }
                    return
                }
                switch new {
                case .landscapeLeft, .landscapeRight, .portrait:
                    self.uiOrientation = new
                default:
                    break
                }
            }
        }
    }

    private func showPermissionsView() {
        guard self.permissionsView == nil else {
            return
        }
        Logging.log("Permissions View Shown")
        let view = PermissionsView.create(frame: self.view.bounds, delegate: self)
        self.permissionsView = view
        self.view.insertSubview(view, aboveSubview: self.navigationHeaderView)
    }

    private func showOptions() {
        guard case .react = self.mode, let content = self.relatedContentEntries.last?.content, !self.isRecordingSession else {
            return
        }

        let sheet = ActionSheetController(title: content.title)
        if content.relatedCount > 0 {
            sheet.addAction(Action("👉 \(content.relatedCount.countLabelShort) Reactions", style: .default) { _ in
                Logging.log("Creation View Options", ["Action": "Watch Reactions"])
                TabBarController.select(originalContent: content, source: "Creation Options")
            })
        }
        sheet.addAction(Action("Request Reactions", style: .default) { _ in
            Logging.log("Creation View Options", ["Action": "Request Reactions"])
            self.shareReactionRequest()
        })
        sheet.addCancel() {
            Logging.log("Creation View Options", ["Action": "Request Reactions"])
        }
        sheet.configurePopover(sourceView: self.topRightBar)
        self.present(sheet, animated: true)
    }

    @objc private dynamic func hidePresentation() {
        guard self.isPresenting else { return }
        self.isPresenting = false
        self.presentationView.attachment = .none
        self.presentationView.isHidden = true
        self.markerView.isHidden = true
        self.refreshActions()
        self.updateComposerFrames()
    }

    @objc private dynamic func showPresentation() {
        guard !self.isPresenting else {
            return
        }
        self.isPresenting = true
        self.presentationView.isHidden = false
        self.markerView.isHidden = true
        self.hideVideoView()
        self.refreshActions()
        self.updateComposerFrames()
    }

    private func hideVideoView() {
        guard !self.videoView.isHidden else {
            return
        }

        if case .none = self.presentationView.attachment {
            // There's nothing to show behind the video view, so just close creation instead.
            self.dismiss()
            return
        }

        self.view.insertSubview(self.presentationView, at: 0)

        if let id = self.pageInfo?.mediaId {
            self.presentationView.notifyMediaScript(id: id, type: "pause")
        }

        let videoAnim = POPBasicAnimation(propertyNamed: kPOPViewFrame)!
        videoAnim.duration = 0.2
        videoAnim.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
        let from = self.videoView.frame
        videoAnim.fromValue = from
        videoAnim.toValue = CGRect(origin: CGPoint(x: from.origin.x, y: UIScreen.main.bounds.height), size: from.size)
        videoAnim.completionBlock = { (_, _) in
            self.videoView.isHidden = true
            self.videoView.clearVideo()
            self.refreshActions()
            self.viewDidLayoutSubviews()
            self.updateTitleLabel()
        }
        self.videoView.pop_add(videoAnim, forKey: "frame")

        self.updateComposerFrames()
        self.refresh()

        if Recorder.instance.state == .recording {
            self.tooltipView.setText("Tap to pause recording")
            self.tooltipView.show(temporary: true)
        } else {
            self.tooltipView.hideAnimated()
        }
    }

    private func showVideoView() {
        guard self.videoView.isHidden else {
            return
        }
        self.videoView.frame = UIScreen.main.bounds
        self.videoView.alpha = 0
        self.videoView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        self.videoView.isHidden = false
        self.videoView.layoutSubviews()
        UIView.animate(withDuration: 0.2, animations: {
            self.videoView.alpha = 1
            self.videoView.transform = .identity
        }) { _ in
            self.presentationView.removeFromSuperview()
        }
        self.refreshActions()
        self.updateComposerFrames()
        self.viewDidLayoutSubviews()
        self.updateTitleLabel()
    }

    private func showRecorderPreview() {
        // Show permissions view if any of the permissions are not granted.
        guard case .react = self.mode, PermissionsView.hasPermissions else {
            return
        }
        if Recorder.instance.state == .idle {
            Recorder.instance.startPreviewing()
        }
        self.recordBar.recordButton.baseDuration = self.content.duration

        if !self.isCameraOnly {
            self.recordPreviewView.hookPreview()
            self.recordPreviewView.isHidden = false
        } else if self.previewFilterIndex != 0, let preview = self.filteredCameraPreview {
            preview.layer.addSublayer(Recorder.instance.hookCameraPreview())
            preview.isPaused = false
        } else {
            let previewLayer = Recorder.instance.hookCameraPreview()
            self.cameraPreviewContainer.layer.addSublayer(previewLayer)
            previewLayer.frame = self.cameraPreviewContainer.bounds
        }
    }

    private func showWebPageAlert() {
        let alert = UIAlertController(title: "Search", message: nil, preferredStyle: .alert)
        alert.addTextField(configurationHandler: { textField in
            textField.keyboardAppearance = .dark
            textField.keyboardType = .webSearch
            textField.placeholder = "Search or enter website name"
            textField.returnKeyType = .go
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Go", style: .default, handler: { _ in
            guard let text = alert.textFields?.first?.text, !text.isEmpty else {
                return
            }
            var url: URL
            if text.contains(".") {
                guard let u = URL(string: text.contains("://") ? text : "https://\(text)") else {
                    return
                }
                url = u
            } else {
                // Turn the text into a query if it doesn't contain a period.
                url = SettingsManager.searchURL(for: text)
            }
            self.presentationView.attachment = .webPage(url)
            self.showPresentation()
        }))
        alert.textFields?.first?.delegate = self
        self.present(alert, animated: true)
    }

    private func showWebPageSheet() {
        let showSearch = {
            let alert = UIAlertController(title: "YouTube", message: nil, preferredStyle: .alert)
            alert.addTextField(configurationHandler: { textField in
                textField.keyboardAppearance = .dark
                textField.keyboardType = .webSearch
                textField.placeholder = "Search YouTube videos"
                textField.returnKeyType = .search
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Search", style: .default, handler: { _ in
                guard let text = alert.textFields?.first?.text, !text.isEmpty else {
                    return
                }
                self.presentationView.attachment = .webPage(SettingsManager.searchURL(for: text, context: .video))
                self.hideVideoView()
                self.showPresentation()
            }))
            alert.textFields?.first?.delegate = self
            self.present(alert, animated: true)
        }

        guard let url = self.clipboardURL else {
            showSearch()
            return
        }

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "🔗 \(url.absoluteString)", style: .default) { _ in
            self.presentationView.attachment = .webPage(url)
            self.showPresentation()
        })
        sheet.addAction(UIAlertAction(title: "YouTube", style: .default) { _ in
            showSearch()
        })
        sheet.addCancel()
        if let button = self.recordBar.button(for: .presentWeb) {
            sheet.configurePopover(sourceView: button)
        }
        self.present(sheet, animated: true)
    }
    
    private func startRecording() {
        guard case .react = self.mode, !self.isRecording && !self.isMergingAssets && !self.recordBar.recordButton.isLoading else {
            return
        }

        guard PermissionsView.hasPermissions else {
            self.showPermissionsView()
            return
        }

        self.countDown {
            self.isRecording = true

            if self.startPlaybackOnRecord {
                self.startPlaybackOnRecord = false
                self.videoView.play()
            }

            self.addRelatedContentEntryFromPageInfo()
            self.relatedContentEntries.last?.visibleInRecording = true

            // Do not allow screen to turn off while recording.
            UIApplication.shared.isIdleTimerDisabled = true
            if
                let camera = self.cameraLayer,
                let presentation = self.presentationLayer,
                let video = self.videoLayer,
                let marker = self.markerLayer
            {
                // Set up the layers to be rendered in the recording.
                var layers: [ComposerLayer] = [camera, presentation, video, marker]
                if let brandImage = self.brandImageLayer {
                    layers.append(contentsOf: [brandImage])
                }
                if let username = self.usernameLayer {
                    layers.append(contentsOf: [username])
                }
                Recorder.instance.layers = layers
            }
            self.updateComposerFrames()
            Recorder.instance.startRecording(quality: self.quality)
            self.recordBar.recordButton.baseDuration = self.content.duration
            self.recordBar.recordButton.recordingState = .recording
            self.tooltipView.stopBouncing()
            self.tooltipView.setText("Recording – tap to pause")
            self.tooltipView.show(temporary: true)
            self.refreshActions()
        }
    }

    private func stopRecording(cancel: Bool = false) {
        DispatchQueue.main.async {
            guard self.isRecording else { return }
            self.tooltipView.hideAnimated()
            self.recordBar.recordButton.isLoading = true
            self.recordBar.recordButton.recordingState = .paused
            self.videoView.pause()
        }
        Recorder.instance.finishRecording() { recording in
            Recorder.instance.zoom(to: 1)
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                Logging.debug("Recording Session Stopped", [
                    "Face Count Average": self.faceCount,
                    "Face Count Max": self.faceCountMax,
                    "Cancelled": cancel,
                    "Duration": recording.duration.seconds])
                self.faceCount = 0
                self.faceCountMax = 0
                self.isRecording = false
                self.markerView.isHidden = true
                if !cancel && recording.duration.seconds > 1 {
                    self.content.assets.append(recording)

                    self.isMergingAssets = true
                    self.recordBar.recordButton.isLoading = true
                    self.refreshActions()
                    // TODO: Make merge private.
                    self.content.merge {
                        defer {
                            self.isMergingAssets = false
                            self.refreshActions()
                        }
                        guard let asset = $0 else {
                            self.recordBar.recordButton.isLoading = false
                            return
                        }
                        // TODO: Don't do this!
                        self.content.assets = [asset]
                        self.content.related = self.lastVisibleRelatedContentEntry
                        self.content.upload()
                        // TODO: Run the code inside this block synchronously without merging.
                        DispatchQueue.main.async {
                            self.recordBar.recordButton.isLoading = false
                            self.goToReview()
                        }
                    }
                } else {
                    self.recordBar.recordButton.isLoading = false
                    self.refresh()
                    self.refreshActions()
                    if cancel {
                        self.tooltipView.setText("Recording failed – try again")
                    } else {
                        self.tooltipView.setText("Too short – try again")
                    }
                    self.tooltipView.show(temporary: true)
                }
            }
        }
    }

    private func save(source: String, completion: @escaping (String?) -> ()) {
        self.statusIndicatorView.showLoading(title: "Saving to Photos")
        self.content.save(source: source) { localId in
            if localId != nil {
                self.statusIndicatorView.showConfirmation()
            } else {
                self.statusIndicatorView.hide()
            }
            completion(localId)
        }
    }

    private func updateComposerFrames() {
        guard
            let camera = self.cameraLayer,
            let presentation = self.presentationLayer,
            let video = self.videoLayer,
            let marker = self.markerLayer
            else { return }
        let videoSize = self.videoView.naturalSize
        // TODO: Do something better about preferredTransform.
        var t = self.videoView.preferredTransform
        t.tx = 0
        t.ty = 0
        video.transform = t
        // Set up visibility of the composer layers.
        video.isHidden = self.videoView.isHidden || videoSize == .zero
        presentation.isHidden = self.presentationView.isHidden || !video.isHidden
        marker.isHidden = self.markerView.isHidden
        // Update the composer layer frames based on the current camera and content conditions.
        let size = MediaWriterSettings.size(quality: self.quality, orientation: self.uiOrientation)
        let contentSize = !video.isHidden ? videoSize : (!presentation.isHidden ? self.presentationView.bounds.size : .zero)
        let config = self.pipConfig.closestConfigFor(camera: size, content: contentSize, in: size)
        let frames = config.framesFor(camera: size, content: contentSize, in: size)
        camera.frame = frames.camera
        if !video.isHidden {
            video.frame = frames.content
        } else if !presentation.isHidden {
            presentation.frame = frames.content
        }
        if config.isContentAbove {
            Recorder.instance.move(layer: camera, below: presentation)
        } else {
            Recorder.instance.move(layer: camera, above: video)
        }
        marker.frame = video.isHidden && presentation.isHidden ? frames.camera : frames.content
        // Update the record preview in the corner.
        self.recordPreviewView.updateFrames(config: config, camera: size, content: contentSize, in: size, orientation: self.uiOrientation)
        print("Picture-in-Picture config: \(config)")
        // Position watermark in top right.
        if let brandLayer = self.brandImageLayer {
            let qScale: CGAffineTransform
            switch self.quality {
            case .medium:
                qScale = .identity
            case .high:
                qScale = CGAffineTransform(scaleX: 1.5, y: 1.5)
            }
            let halfQScale = qScale.concatenating(CGAffineTransform(scaleX: 0.5, y: 0.5))

            let brandSize = CGSize(width: 350, height: 56).applying(qScale)
            brandLayer.frame = CGRect(
                origin: CGPoint(x: size.width - brandSize.width - 8, y: 6),
                size: brandSize)

            if let usernameLayer = self.usernameLayer {
                let usernameSize = ((usernameLayer.provider as! ConstantTexture).size).applying(halfQScale)
                usernameLayer.frame = CGRect(
                    origin: CGPoint(x: size.width - usernameSize.width - 16, y: brandSize.height - 2),
                    size: usernameSize)
            }
        }
    }

    private func updateFlash() {
        guard self.flash else {
            self.disableFlash()
            return
        }
        self.videoView.backgroundColor = .white
        switch Recorder.instance.configuration {
        case .backCamera:
            Recorder.instance.toggleTorch(on: true)
        case .frontCamera:
            self.frontBlixtView.isHidden = false
        default:
            break
        }
    }

    private func updateTitleLabel() {
        var text: String
        if case .request = self.mode {
            text = "Reaction Request"
        } else {
            text = ""
            if let username = self.requesterUsername {
                text += "@\(username): "
            }
            if let title = self.pageInfo?.cleanTitle, !title.isEmpty {
                text += title
            } else if let entry = self.relatedContentEntries.last, case .id = entry.ref {
                if let title = entry.content?.title {
                    text += title
                } else {
                    text += "New Reaction"
                }
            } else if self.isCameraOnly {
                text += "🔍 google anything to react"
            }
        }

        self.titleButton.setTitle(text, for: .normal)
        self.landscapeTitleLabel.text = text
        self.landscapeTitleLabel.setSoftShadow()

        if self.uiOrientation != .portrait && !self.videoView.isHidden {
            self.landscapeTitleLabel.isHidden = false
            self.titleButton.titleLabel?.textColor = UIColor.white.withAlphaComponent(0.05)
        } else {
            self.landscapeTitleLabel.isHidden = true
            self.titleButton.titleLabel?.textColor = UIColor.white
        }
    }

    // MARK: - Events

    @objc private dynamic func updateHeadphonesAlert() {
        DispatchQueue.main.async {
            if case .react = self.mode,
                AudioService.instance.isHeadphonesConnected,
                self.showSoundAlerts {
                self.soundAlertLabel.text = "Remove headphones to record audio"
                self.soundAlertView.blink()
            } else {
                self.soundAlertView.hideAnimated()
            }
        }
    }

    private func updateSoundAlert(volume: Float? = nil) {
        DispatchQueue.main.async {
            if
                case .react = self.mode,
                AudioService.instance.isLoudspeaker,
                (volume ?? AVAudioSession.sharedInstance().outputVolume) > self.maxVolume,
                self.showSoundAlerts {
                self.soundAlertLabel.text = "Lower volume to record your voice"
                self.soundAlertView.blink()
            } else {
                self.soundAlertView.hideAnimated()
                self.updateHeadphonesAlert()
            }
        }
    }

    private func handleApplicationActiveStateChanged(active: Bool) {
        guard active else {
            // Pre-emptively stop recording to avoid losing content.
            self.stopRecording()
            return
        }
        self.refresh()
    }

    private func handleSessionChanged() {
        self.setWatermark()
    }

    private func handleFaceDetected(faces: [AVMetadataFaceObject]) {
        let newCount = Double(faces.count)
        if newCount > self.faceCount {
            self.faceCount = (self.faceCount * 9.0 + newCount) / 10.0
        } else {
            self.faceCount = (self.faceCount * 99.0 + newCount) / 100.0
        }
        self.faceCountMax = max(self.faceCountMax, self.faceCount)
        guard let face = faces.first else {
            return
        }
        if
            let texture = self.cameraTexture,
            let filter = texture.filter,
            filter.name == "CIZoomBlur"
        {
            let vector: CIVector
            switch self.uiOrientation {
            case .landscapeLeft:
                vector = CIVector(x: (1 - face.bounds.midX) * texture.size.width,
                                  y: (1 - face.bounds.midY) * texture.size.height)
            case .landscapeRight:
                vector = CIVector(x: face.bounds.midX * texture.size.width,
                                  y: face.bounds.midY * texture.size.height)
            default:
                vector = CIVector(x: (1 - face.bounds.midY) * texture.size.width,
                                  y: face.bounds.midX * texture.size.height)
            }
            filter.setValue(vector, forKey: "inputCenter")
        }
        Recorder.instance.focus(point: CGPoint(x: face.bounds.midX, y: face.bounds.midY))
    }

    private func handleRecorderUnavailable(reason: AVCaptureSession.InterruptionReason) {
        if Recorder.instance.state == .recording {
            // Recording will crash if it tries to continue in background.
            self.stopRecording()
        }
        switch reason {
        case .audioDeviceInUseByAnotherClient:
            // Probably in a phone call.
            break
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            guard Recorder.instance.configuration != .audioOnly else {
                return
            }
            self.enterAudioMode()
            self.refreshActions()
            if UIApplication.shared.applicationState == .active {
                let alert = UIAlertController(title: "Video Unavailable", message: "To record video, go into full screen mode.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
            }
        default:
            break
        }
    }

    private func handleUnplayedCountChanged() {
        self.refresh()
    }

    private func incrementFilterIndex(by amount: Int) {
        guard amount != 0 else { return }
        self.previewFilterIndex = (self.availableFilters.count + self.previewFilterIndex + amount) % self.availableFilters.count
        self.selectFilter(filterIndex: self.previewFilterIndex)

    }

    private func selectFilter(filterIndex: Int) {
        let filter = self.availableFilters[filterIndex]
        self.filterLabel.text = filter.name
        Logging.debug("Preview Filter", ["Filter": filter.name])
        if filter.id.isEmpty {
            self.cameraTexture?.filter = nil
        } else {
            let ciFilter = CIFilter(name: filter.id)
            for (key, value) in filter.values {
                ciFilter?.setValue(value, forKey: key)
            }
            self.cameraTexture?.filter = ciFilter
        }
    }

    private func shareReactionRequest() {
        guard let content = self.relatedContentEntries.last?.content else {
            return
        }
        self.videoView.pause()
        if let url = content.webURL {
            var copy = url.absoluteString
            if let title = content.title, !title.isEmpty {
                copy = title + " " + copy
            }
            let share = UIActivityViewController(activityItems: [DynamicActivityItem(copy)], applicationActivities: nil)
            share.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
            share.completionWithItemsHandler = { activity, success, _, _ in
                guard success else {
                    return
                }
                Logging.success("Share Success", [
                    "Destination": activity?.rawValue ?? "Other",
                    "Duration": content.duration,
                    "Source": self.source,
                    "Type": "ReactionLink"])
            }
            share.configurePopover(sourceView: self.topRightBar)
            self.present(share, animated: true)
        } else {
            guard let share = Bundle.main.loadNibNamed("ShareViewController", owner: nil, options: nil)?.first as? ShareViewController else {
                return
            }
            share.mode = .request(content: content)
            share.source = self.source
            if case .request = self.mode {
                share.showFinish = true
            }
            self.navigationController?.pushViewController(share, animated: true)
        }
    }
    
    private func showOrientationError(duration: TimeInterval? = nil) {
        guard self.rotationAlertContainerView.isHidden else {
            return
        }
        Logging.warning("Rotation Error Dialog")
        let rotation: CGFloat
        switch self.uiOrientation {
        case .landscapeLeft:
            rotation = .pi / 2
        case .landscapeRight:
            rotation = .pi / -2
        default:
            rotation = 0
        }
        let transform = CGAffineTransform(rotationAngle: rotation)
        self.rotationAlertView.transform = transform
        self.rotationAlertContainerView.alpha = 1
        self.rotationAlertContainerView.isHidden = false
        if let duration = duration {
            UIView.animate(withDuration: 0.2, delay: duration, options: [], animations: {
                self.rotationAlertContainerView.alpha = 0
            }) { _ in
                self.rotationAlertContainerView.isHidden = true
            }
        }
    }

    private func hideOrientationError(delay: TimeInterval = 0.0) {
        UIView.animate(withDuration: 0.2, delay: delay, options: [], animations: {
            self.rotationAlertContainerView.alpha = 0
        }) { _ in
            self.rotationAlertContainerView.isHidden = true
        }
    }

    private func showTutorial() {
        self.tutorialDoneButton.alpha = 0
        self.tutorialView.showAnimated()
        UIView.animate(withDuration: 0.2, delay: 2.0, options: [], animations: {
            self.tutorialDoneButton.alpha = 1
        })
    }
}
