import AVFoundation
import FBSDKLoginKit
import FBSDKShareKit
import iRate
import MessageUI
import MobileCoreServices
import Photos
import SafariServices
import TwitterKit
import TMTumblrSDK
import UIKit

fileprivate let placeholder = "title, #tags & @mentions ✍️"

class ReviewViewController: UIViewController,
    SFSafariViewControllerDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    UITextViewDelegate,
    OriginalPickerDelegate,
    SearchViewDelegate,
    ThumbnailPickerDelegate,
    VideoTrimmerDelegate,
    VideoViewDelegate,
    MFMessageComposeViewControllerDelegate {

    var content: PendingContent! {
        didSet {
            self.updateContent()
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    var source = "Unknown"

    // MARK: - Outlets

    @IBOutlet weak var autopostReactionCamSwitch: UISwitch!
    @IBOutlet weak var autopostFacebookSwitch: UISwitch!
    @IBOutlet weak var autopostIGTVSwitch: UISwitch!
    @IBOutlet weak var autopostInstagramSwitch: UISwitch!
    @IBOutlet weak var autopostTumblrSwitch: UISwitch!
    @IBOutlet weak var autopostTwitterSwitch: UISwitch!
    @IBOutlet weak var autopostYouTubeSwitch: UISwitch!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var igtvRulesLabel: UILabel!
    @IBOutlet weak var itemAutopostFacebook: UIView!
    @IBOutlet weak var itemAutopostIGTV: UIView!
    @IBOutlet weak var itemAutopostInstagram: UIView!
    @IBOutlet weak var itemAutopostReactionCam: UIView!
    @IBOutlet weak var itemAutopostTumblr: UIView!
    @IBOutlet weak var itemAutopostTwitter: UIView!
    @IBOutlet weak var itemAutopostYouTube: UIView!
    @IBOutlet weak var itemRecordMoreView: UIView!
    @IBOutlet weak var linkButton: UIButton!
    @IBOutlet weak var linkImagePlaceholderLabel: UILabel!
    @IBOutlet weak var linkImageView: UIImageView!
    @IBOutlet weak var linkView: UIView!
    @IBOutlet weak var originalRefView: UIView!
    @IBOutlet weak var originalLabel: UILabel!
    @IBOutlet weak var playerContainer: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var shareLabel: UILabel!
    @IBOutlet weak var shareVideoButton: UIButton!
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var titleTextView: UITextView!

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.videoView.frame = self.playerContainer.bounds
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(ReviewViewController.anywhereTapped))
        tap.isEnabled = false
        self.view.addGestureRecognizer(tap)
        self.anywhereTapRecognizer = tap

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.scrollView.keyboardDismissMode = .onDrag
        self.scrollView.showsVerticalScrollIndicator = true
        self.scrollView.indicatorStyle = .white

        let video = VideoView(frame: self.playerContainer.bounds)
        video.delegate = self
        self.playerContainer.insertSubview(video, at: 0)
        self.videoView = video
        self.videoView.orientation = .portrait

        switch self.content.type {
        case .recording:
            self.titleLabel.text = "New Video"
        case .repost:
            self.titleLabel.text = "Repost Video"
            self.itemRecordMoreView.isHidden = true
        case .upload:
            self.titleLabel.text = "Upload Video"
            self.itemRecordMoreView.isHidden = true
        }

        
        if let url = self.content.mergedAsset?.generateThumbnail()?.save(temporary: false) {
            self.content.thumbnailURL = url
            self.thumbnailImageView.af_setImage(withURL: url)
        }

        self.updateContent()
        self.updateTitle()
        
        if case let .recording(isVlog) = self.content.type, isVlog {
            self.originalRefView.isHidden = true
        } else if let related = self.content.related?.ref {
            if case let .metadata(_, _, _, title, _, _) = related {
                // TODO: Get thumbURL
                self.originalLabel.text = title
                self.originalLabel.textColor = UIColor.white
            }
        }

        self.titleTextView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        self.titleTextView.tintColor = .uiYellow
        self.titleTextView.autocorrectionType = .yes
        self.titleTextView.delegate = self
        self.textViewDidEndEditing(self.titleTextView)

        self.imagePicker.sourceType = .photoLibrary
        self.imagePicker.mediaTypes = [kUTTypeMovie as String]
        self.imagePicker.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(ReviewViewController.keyboardEvent),
                                               name: .UIKeyboardWillChangeFrame, object: nil)

        ContentService.instance.serviceConnected.addListener(self, method: ReviewViewController.handleServiceConnected)

        // Make toggle rows tapable
        self.itemAutopostFacebook.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ReviewViewController.facebookAutopostTapped)))
        self.itemAutopostIGTV.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ReviewViewController.igtvAutopostTapped)))
        self.itemAutopostInstagram.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ReviewViewController.instagramAutopostTapped)))
        self.itemAutopostReactionCam.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ReviewViewController.reactionCamAutopostTapped)))
        self.itemAutopostTumblr.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ReviewViewController.tumblrAutopostTapped)))
        self.itemAutopostTwitter.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ReviewViewController.twitterAutopostTapped)))
        self.itemAutopostYouTube.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ReviewViewController.youTubeAutopostTapped)))

        self.linkView.isHidden = true
        self.linkButton.titleLabel?.adjustsFontSizeToFitWidth = true
        self.linkView.insertSubview(self.cheerView, at: 0)
        self.cheerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.cheerView.frame = self.linkView.bounds
        self.cheerView.config.particle = .confetti
        self.cheerView.alpha = 0.7
        
        let searchView = Bundle.main.loadNibNamed("SearchView", owner: nil, options: nil)?.first as! SearchView
        searchView.delegate = self
        searchView.frame = self.view.bounds
        searchView.isHidden = true
        searchView.presenter = self
        self.view.addSubview(searchView)
        self.searchView = searchView
    }

    override func viewWillAppear(_ animated: Bool) {
        Logging.debug("Review Appeared", [
            "DiskSpace": FileManager.default.freeDiskSpace ?? -1,
            "Source": self.source])
        super.viewWillAppear(animated)
        self.videoView.play()
        AppDelegate.applicationActiveStateChanged.addListener(self, method: ReviewViewController.handleApplicationActiveStateChanged)

        self.autopostFacebookSwitch.isOn = (FBSDKAccessToken.current()?.permissions?.contains("publish_actions") ?? false) && !self.facebookToggledOff
        self.autopostTumblrSwitch.isOn = TMAPIClient.sharedInstance().oAuthToken != nil && !self.tumblrToggledOff
        if let twitterUser = TWTRTwitter.sharedInstance().sessionStore.session(), !self.twitterToggledOff {
            self.autopostTwitterSwitch.isOn = true
            // check if Twitter token still valid
            TWTRAPIClient(userID: twitterUser.userID).loadUser(withID: twitterUser.userID) { user, error in
                if let error = error, let code = (error as NSError).userInfo["TWTRNetworkingStatusCode"] as? Int64, code == 401  {
                    TWTRTwitter.sharedInstance().sessionStore.logOutUserID(twitterUser.userID)
                    self.autopostTwitterSwitch.isOn = false
                }

            }
        }
        if let session = BackendClient.api.session, session.hasService(id: "youtube") && !self.youTubeToggledOff {
            self.autopostYouTubeSwitch.isOn = true
        }

        // Don't allow the user to switch YouTube when there's a request
        self.autopostYouTubeSwitch.isEnabled = self.content.request == nil

        self.itemAutopostTumblr.isHidden = true
        self.autopostReactionCamSwitch.isOn = !self.reactionCamToggledOff

        // TODO decide on removing/reverting based on data
        self.itemAutopostReactionCam.isHidden = true

        // TODO remove if keeping IGTV
        self.itemAutopostInstagram.isHidden = true
        self.autopostInstagramSwitch.isOn = !self.itemAutopostInstagram.isHidden && SettingsManager.autopostInstagram

        if
            let recordingAspect = self.content.assets[0].tracks(withMediaType: .video).first?.naturalSize.aspectRatio,
            recordingAspect < 1,
            self.content.duration > 15 {
            self.autopostIGTVSwitch.isEnabled = true
            self.igtvRulesLabel.isHidden = true
        } else {
            self.autopostIGTVSwitch.isEnabled = false
            self.igtvRulesLabel.isHidden = false
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AppDelegate.applicationActiveStateChanged.removeListener(self)
        self.videoView.pause()
    }

    // MARK: - Actions

    @IBAction func addIntroButton(_ sender: Any) {
        Logging.log("Review View Controller", ["Action": "Add Intro"])
        guard let recordingAspect = self.content.assets[0].tracks(withMediaType: .video).first?.naturalSize.aspectRatio else {
            return
        }
        // This is to prevent a crash due to this event registering twice.
        guard !self.doubleTapProtection else {
            return
        }
        self.doubleTapProtection = true
        // Tell the user that their intro needs to be in the same orientation.
        self.appendVideoAsIntro = true
        let alert = AnywhereAlertController(
            title: "Pick a \(recordingAspect > 1 ? "HORIZONTAL video ↔️" : "VERTICAL VIDEO ↕️")",
            message: "💁‍♀️ Square or \(recordingAspect > 1 ? "vertical" : "horizontal") intros wouldn't match your video and get squeezed.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.present(self.imagePicker, animated: true)
            self.doubleTapProtection = false
        })
        alert.show()
    }

    @IBAction func addOutroButton(_ sender: Any) {
        Logging.log("Review View Controller", ["Action": "Add Outro"])
        guard let recordingAspect = self.content.assets[0].tracks(withMediaType: .video).first?.naturalSize.aspectRatio else {
            return
        }
        // This is to prevent a crash due to this event registering twice.
        guard !self.doubleTapProtection else {
            return
        }
        self.doubleTapProtection = true
        // Tell the user that their outtro needs to be in the same orientation.
        self.appendVideoAsIntro = false
        let alert = AnywhereAlertController(
            title: "Pick a \(recordingAspect > 1 ? "HORIZONTAL video ↔️" : "VERTICAL VIDEO ↕️")",
            message: "💁‍♀️ Square or \(recordingAspect > 1 ? "vertical" : "horizontal") outros wouldn't match your video and get squeezed.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.present(self.imagePicker, animated: true)
            self.doubleTapProtection = false
        })
        alert.show()
    }

    @IBAction func closeTapped(_ sender: AnyObject) {
        self.content.title = self.getTitle()
        self.navigationController?.popViewController(animated: true)
        Logging.log("Review View Controller", ["Action": "Back"])
    }

    @IBAction func closeLinkTapped(_ sender: Any) {
        Logging.log("Review View Controller", ["Action": "Close Link"])
        self.finish()
    }

    @IBAction func cropVideoTapped(_ sender: UIButton) {
        Logging.log("Review View Controller", ["Action": "Crop Video"])
        self.showTrimmer(source: "CropVideoButton")
    }

    @IBAction func editOriginalTapped(_ sender: Any) {
        self.searchView.show()
    }
    
    @IBAction func editThumbnailTapped(_ sender: Any) {
        Logging.log("Review View Controller", ["Action": "Edit"])
        guard let asset = self.content.mergedAsset,
            let thumbnailPicker = Bundle.main.loadNibNamed("ThumbnailPickerViewController", owner: nil, options: nil)?.first as? ThumbnailPickerViewController else {
                return
        }
        thumbnailPicker.delegate = self
        thumbnailPicker.load(asset: asset)
        self.present(thumbnailPicker, animated: true)
    }

    @IBAction func helpTapped(_ sender: Any) {
        Logging.log("Review View Controller", ["Action": "Help"])
        HelpViewController.showHelp(presenter: self)
    }

    @IBAction func linkTapped(_ sender: Any) {
        Logging.log("Review View Controller", ["Action": "Link Tapped"])
        UIPasteboard.general.string = self.shareURL.absoluteString
        self.statusIndicatorView.showConfirmation(title: "Link Copied")
    }

    @IBAction func shareLinkTapped(_ sender: Any) {
        Logging.log("Review View Controller", ["Action": "Share Link"])
        self.showShareLink(sourceView: self.shareVideoButton)
    }
    
    @IBAction func shareTapped(_ sender: UIButton) {
        self.titleTextView.resignFirstResponder()
        guard !self.didPublish else {
            return
        }

        // Show loading state while we get the share link.
        // TODO: Either make this wait for a content id, or make it work offline.
        self.didPublish = true
        self.statusIndicatorView.showLoading(title: "Just a sec...")
        self.view.isUserInteractionEnabled = false

        // Figure out external destinations.
        let switches = [
            "CameraRoll": self.content.isSaved,
            "Facebook": self.autopostFacebookSwitch.isOn,
            "IGTV": self.autopostIGTVSwitch.isOn,
            "Instagram": self.autopostInstagramSwitch.isOn,
            "Tumblr": self.autopostTumblrSwitch.isOn,
            "Twitter": self.autopostTwitterSwitch.isOn,
            "YouTube": self.autopostYouTubeSwitch.isOn,
            ]
        let choices = switches.filter({ $0.value }).keys.sorted()
        let destinations = choices.isEmpty ? "Nowhere" : choices.joined(separator: ",")

        // Configure the pending content.
        self.content.extraMetadata["destinations"] = destinations
        self.content.extraMetadata["source"] = self.source
        self.content.title = self.getTitle()
        self.content.postToFacebook = self.autopostFacebookSwitch.isOn
        self.content.postToTumblr = self.autopostTumblrSwitch.isOn
        self.content.postToTwitter = self.autopostTwitterSwitch.isOn
        self.content.postToYouTube = self.autopostYouTubeSwitch.isOn

        // Queue creation of the content.
        let promise = self.content.create()

        // Make sure a placeholder entry exists for the request this reaction is for.
        if let request = self.content.request {
            ContentService.instance.submitPublicRequestEntry(request.id, contentId: nil, source: "Share Public Tapped")
        }

        // Log that the user successfully shared a piece of content.
        Logging.success("Share Public Tapped", [
            "Duration": self.content.duration,
            "Destinations": destinations,
            "Source": self.source,
            "Upload Job Id": self.content.uploadJobId ?? "N/A",
            ].merging(switches) { pair, _ in pair })
        iRate.sharedInstance().logEvent(true)

        // Wait for share URL, then show link party.
        let party: (URL) -> () = { url in
            self.shareURL = url
            let urlString = url.absoluteString
            DispatchQueue.main.async {
                self.hideLoading()
                self.videoView.clearVideo()
                self.cheerView.start()
                self.linkButton.setTitle(urlString.replacingOccurrences(of: "https://www.reaction.cam", with: "rcam.at"), for: .normal)
                if let thumbURL = self.content.thumbnailURL {
                    self.linkImageView.af_setImage(withURL: thumbURL)
                    self.linkImageView.isHidden = false
                    self.linkImagePlaceholderLabel.isHidden = true
                } else {
                    self.linkImageView.isHidden = true
                    self.linkImagePlaceholderLabel.isHidden = false
                }
                self.linkView.showAnimated()
                self.showShareLink(sourceView: self.shareVideoButton)
            }
        }
        if self.autopostIGTVSwitch.isOn {
            self.shareToIGTV() {
                promise
                    .then { _ in self.finishOnMain() }
                    .catch { _ in self.finishOnMain() }
            }
        } else {
            promise
                .then { _ in self.finishOnMain() }
                .catch { _ in self.finishOnMain() }
        }
    }

    @IBAction func youTubeAutopostToggled(_ sender: UISwitch) {
        self.youTubeToggledOff = !sender.isOn

        guard sender.isOn else {
            Logging.debug("YouTube Autopost Toggle", ["Result": false])
            return
        }
        guard let session = BackendClient.api.session else {
            return
        }
        guard session.hasService(id: "youtube") else {
            self.youTubeConnect()
            return
        }
        Logging.debug("YouTube Autopost Toggle", ["Result": true])
        SettingsManager.autopostYouTube = true
    }

    @IBAction func facebookAutopostToggled(_ sender: UISwitch) {
        self.facebookToggledOff = !sender.isOn

        guard sender.isOn else {
            Logging.log("Facebook Autopost Toggle", ["Result": false])
            return
        }
        let permission = "publish_actions"
        if let token = FBSDKAccessToken.current(), token.hasGranted(permission) {
            SettingsManager.autopostFacebook = true
            return
        }
        self.statusIndicatorView.showLoading()
        AppDelegate.connectFacebook(presenter: self) { success in
            guard success else {
                Logging.log("Facebook Autopost Toggle", ["Result": success])
                self.autopostFacebookSwitch.isOn  = false
                self.statusIndicatorView.hide()
                return
            }
            let login = FBSDKLoginManager()
            login.logIn(withPublishPermissions: [permission], from: self) { session, error in
                self.statusIndicatorView.hide()
                let success = session?.grantedPermissions?.contains(permission) ?? false
                self.autopostFacebookSwitch.isOn = success
                Logging.log("Facebook Autopost Toggle", ["Result": true])
            }
        }
    }

    @IBAction func igtvAutopostToggled(_ sender: UISwitch) {
        self.igtvToggledOff = !sender.isOn
        SettingsManager.autopostIGTV = sender.isOn

        guard sender.isOn else {
            Logging.debug("IGTV Autopost Toggle", ["Result": false])
            return
        }

        guard UIApplication.shared.canOpenURL(URL(string: "igtv://")!) else {
            Logging.debug("IGTV Autopost Toggle", ["Result": false])
            Logging.log("Review View Controller", ["Action": "IGTV Download"])
            let url = URL(string: "https://itunes.apple.com/us/app/igtv/id1394351700?mt=8")!
            UIApplication.shared.open(url)
            return
        }

        Logging.log("IGTV Autopost Toggle", ["Result": true])
    }

    @IBAction func instagramAutopostToggled(_ sender: UISwitch) {
        self.instagramToggledOff = !sender.isOn
        SettingsManager.autopostInstagram = sender.isOn

        guard sender.isOn else {
            Logging.debug("Instagram Autopost Toggle", ["Result": false])
            return
        }
        Logging.log("Instagram Autopost Toggle", ["Result": true])
    }

    @IBAction func reactionCamAutopostToggled(_ sender: UISwitch) {
        self.reactionCamToggledOff = !sender.isOn

        guard sender.isOn else {
            Logging.debug("Reaction.cam Autopost Toggle", ["Result": false])
            return
        }

        // TODO
    }

    @IBAction func sharingOptionsTapped(_ sender: UIButton) {
        Logging.log("Review View Controller", ["Action": "Sharing Options"])
        guard let session = BackendClient.api.session else {
            return
        }
        let sheet = UIAlertController(title: "Sharing Options", message: nil, preferredStyle: .actionSheet)
        if self.autopostFacebookSwitch.isOn {
            sheet.addAction(UIAlertAction(title: "Edit Facebook Caption", style: .default) { _ in
                Logging.log("Review Sharing Options ", ["Action": "Edit Facebook Caption"])
                let facebookCaptionAlert = UIAlertController(title: "Edit Facebook Caption", message: nil, preferredStyle: .alert)
                facebookCaptionAlert.addTextField(configurationHandler: { textField in
                    textField.keyboardAppearance = .dark
                    textField.keyboardType = .default
                    textField.isSecureTextEntry = false
                    textField.autocorrectionType = .yes
                    textField.placeholder = ""
                    textField.text = self.content.facebookCaption
                    textField.returnKeyType = .done
                })
                facebookCaptionAlert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in
                    guard let fields = facebookCaptionAlert.textFields, let caption = fields[0].text else {
                        return
                    }
                    self.content.facebookCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.statusIndicatorView.showConfirmation()
                })
                facebookCaptionAlert.addCancel(title: "Cancel")
                self.present(facebookCaptionAlert, animated: true)
            })
        }

        if UIApplication.shared.canOpenURL(URL(string: "instagram://")!) {
            sheet.addAction(UIAlertAction(title: "Instagram", style: .default) { _ in
                Logging.log("Review Sharing Options ", ["Action": "Instagram"])
                self.shareToInstagram() {}
            })
        }

        let title = session.hasService(id: "youtube") ? "Change YouTube account" : "Connect YouTube"
        sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
            Logging.log("Review Sharing Options ", ["Action": title])
            self.youTubeConnect()
        })
        sheet.addCancel()
        sheet.configurePopover(sourceView: sender)
        self.present(sheet, animated: true)
    }

    @IBAction func twitterAutopostToggled(_ sender: UISwitch) {
        self.twitterToggledOff = !sender.isOn

        guard sender.isOn else {
            Logging.debug("Twitter Autopost Toggle", ["Result": false])
            return
        }

        guard !TWTRTwitter.sharedInstance().sessionStore.hasLoggedInUsers() else {
            SettingsManager.autopostTwitter = true
            return
        }
        TWTRTwitter.sharedInstance().logIn(with: self) { session, error in
            guard error == nil, session != nil else {
                NSLog("WARNING: Twitter auth failed \(error!)")
                SettingsManager.autopostTwitter = false
                sender.isOn = false
                Logging.debug("Twitter Autopost Toggle", ["Result": false])
                return
            }
            SettingsManager.autopostTwitter = true
            Logging.debug("Twitter Autopost Toggle", ["Result": true])
        }
    }

    @IBAction func tumblrAutopostToggled(_ sender: UISwitch) {
        self.tumblrToggledOff = !sender.isOn

        guard sender.isOn else {
            Logging.debug("Tumblr Autopost Toggle", ["Result": false])
            return
        }

        guard let client = TMAPIClient.sharedInstance(), client.oAuthToken == nil else {
            return
        }
        client.authenticate("cam.reaction.ReactionCam", from: self) { error in
            guard error == nil else {
                NSLog("WARNING: Tumblr auth failed \(error!)")
                SettingsManager.autopostTumblr = false
                sender.isOn = false
                Logging.debug("Tumblr Autopost Toggle", ["Result": false])
                return
            }
            SettingsManager.tumblrOAuthToken = client.oAuthToken
            SettingsManager.tumblrOAuthTokenSecret = client.oAuthTokenSecret
            SettingsManager.autopostTumblr = true
            Logging.debug("Tumblr Autopost Toggle", ["Result": true])
        }
    }

    @IBAction func saveTapped(_ sender: Any) {
        Logging.log("Review View Controller", ["Action": "Save"])
        self.statusIndicatorView.showLoading()

        guard !self.content.isSaved else {
            self.statusIndicatorView.showConfirmation()
            return
        }

        let previousStatus = PHPhotoLibrary.authorizationStatus()
        PHPhotoLibrary.requestAuthorization { status in
            if previousStatus == .notDetermined {
                if status == .authorized {
                    Logging.success("Permission Granted", ["Permission": "Photo Library"])
                } else {
                    Logging.danger("Permission Denied", ["Permission": "Photo Library"])
                }
            }
            guard status == .authorized else {
                let alert = AnywhereAlertController(title: "Can't Save Video", message: "You must grant permission to access Photos to save videos.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    // TODO open Settings when we save the draft otherwise the system will restart the app when changing permissions
                })
                alert.show()
                return
            }
            self.content.save(source: "Review View") { localId in
                if localId != nil {
                    self.statusIndicatorView.showConfirmation()
                } else {
                    self.statusIndicatorView.hide()
                }
            }
        }
    }

    // MARK: - MFMessageComposeViewControllerDelegate

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }

    // MARK: - SFSafariViewControllerDelegate

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        self.autopostYouTubeSwitch.isEnabled = true
        self.autopostYouTubeSwitch.isOn = BackendClient.api.session?.hasService(id: "youtube") ?? false
        self.webController = nil
    }

    // MARK: - UIImagePickerViewControllerDelegate

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Logging.log("Review View Controller", ["Action": "PickMedia", "Result": "Cancel"])
        picker.dismiss(animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String: Any]) {
        guard let url = info[UIImagePickerControllerMediaURL] as? URL else {
            Logging.warning("Review View Controller", [
                "Action": "PickMedia",
                "Result": "Failed",
                "Reason": "NoMediaURL"])
            picker.dismiss(animated: true)
            return
        }
        picker.dismiss(animated: true)

        // TODO: Perform all of the below within PendingContent and don't merge everything.
        self.view.isUserInteractionEnabled = false
        self.statusIndicatorView.showLoading(title: "Importing...")
        let pickedVideo = AVURLAsset(url: url)
        // Apply any embedded preferredTransform
        AssetEditor.sanitize(asset: pickedVideo) {
            guard let video = $0 else {
                picker.dismiss(animated: true)
                self.view.isUserInteractionEnabled = true
                self.statusIndicatorView.hide()
                self.showVideoError()
                Logging.warning("Review View Controller", [
                    "Action": "PickMedia",
                    "Result": "Failed",
                    "Reason": "CouldNotApplyPreferredTransform"])
                return
            }
            let recording = self.content.assets[0]
            guard
                let videoAspect = video.tracks(withMediaType: .video).first?.naturalSize.aspectRatio,
                let recordingAspect = recording.tracks(withMediaType: .video).first?.naturalSize.aspectRatio
            else {
                self.view.isUserInteractionEnabled = true
                self.statusIndicatorView.hide()
                self.showVideoError()
                Logging.warning("Review View Controller", [
                    "Action": "PickMedia",
                    "Result": "Failed",
                    "Reason": "Unknown"])
                return
            }
            guard abs(videoAspect - recordingAspect) < 0.2 else {
                self.view.isUserInteractionEnabled = true
                self.statusIndicatorView.hide()
                let videoType = self.appendVideoAsIntro ? "intro" : "outro"
                let videoFormat: String
                switch videoAspect {
                case 1:
                    videoFormat = "square"
                case ..<1:
                    videoFormat = "vertical"
                default:
                    videoFormat = "horizontal"
                }
                let recordingFormat = recordingAspect > 1 ? "horizontal" : "vertical"
                self.showVideoError(
                    message: "You recorded a \(recordingFormat) video, but picked a \(videoFormat) \(videoType) which would look squeezed.\n\nPick a \(recordingFormat) \(videoType) to add it.",
                    title: "The \(videoType) you picked does not match your video 🧐"
                )
                Logging.warning("Review View Controller", [
                    "Action": "PickMedia",
                    "Result": "Failed",
                    "Reason": "Recorded a \(recordingFormat) video, but picked a \(videoFormat) \(videoType)"])
                return
            }

            AssetEditor.merge(assets: self.appendVideoAsIntro ? [video, recording] : [recording, video]) {
                guard let asset = $0 else {
                    self.view.isUserInteractionEnabled = true
                    self.statusIndicatorView.hide()
                    self.showVideoError()
                    Logging.warning("Review View Controller", [
                        "Action": "PickMedia",
                        "Result": "Failed",
                        "Reason": "CouldNotMerge"])
                    return
                }
                self.view.isUserInteractionEnabled = true
                self.statusIndicatorView.showConfirmation()
                self.content.assets = [asset]
                self.updateContent()
                self.mergeAndUpload()
                Logging.log("Review View Controller", ["Action": "PickMedia", "Result": "Success"])
            }
        }
    }

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        self.anywhereTapRecognizer.isEnabled = true
        self.videoView.isUserInteractionEnabled = false
        self.videoView.hideUI()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines) == placeholder {
            textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.textColor = UIColor(white: 1, alpha: 0.7)
            textView.text = placeholder
            textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
        } else {
            let preAttributedRange: NSRange = textView.selectedRange
            textView.text = textView.text
                .replacingOccurrences(of: placeholder, with: "")
            textView.textColor = .white
            textView.selectedRange = preAttributedRange
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        self.anywhereTapRecognizer.isEnabled = false
        self.videoView.isUserInteractionEnabled = true
        self.videoView.showUI()
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.textColor = UIColor(white: 1, alpha: 0.7)
            textView.text = placeholder
        } else if textView.text != placeholder {
            textView.text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        } else {
            return true
        }
    }

    // MARK: - OriginalPickerDelegate
    
    func originalPicker(_ picker: OriginalPickerViewController, didFinishPicking content: ContentRef) {
        picker.dismiss(animated: true)
        self.content.related = RelatedContentEntry(ref: content)
        if case let .metadata(_, _, _, title, _, _) = content {
            self.originalLabel.text = title
            self.originalLabel.textColor = UIColor.white
            if self.titleTextView.text == placeholder {
                self.titleTextView.text = "\(title) REACTION.CAM"
            }
        }
    }
    
    // MARK: - SearchView
    
    func searchView(_ view: SearchView, didSelect result: SearchView.Result) {
        view.endEditing(true)
        switch result {
        case let .googleQuery(query):
            let picker = self.storyboard?.instantiateViewController(withIdentifier: "OriginalPicker") as! OriginalPickerViewController
            picker.delegate = self
            if let url = query.searchURL() {
                picker.present(url: url)
            }
            self.present(picker, animated: true) {
                view.hideAnimated()
            }
        case let .content(result, _):
            self.originalLabel.text = result.title
            self.originalLabel.textColor = UIColor.white
            if let title = result.title, self.titleTextView.text == placeholder {
                self.titleTextView.text = "\(title) REACTION.CAM"
            }
            self.content.related = RelatedContentEntry(ref: result.ref)
            view.hideAnimated()
        default:
            return
        }
    }

    func searchViewShouldShowAccounts(_ view: SearchView) -> Bool {
        return false
    }

    func searchViewShouldShowAccountsVip(_ view: SearchView) -> Bool {
        return false
    }

    func searchViewShouldShowTags(_ view: SearchView) -> Bool {
        return false
    }

    // MARK: - ThumbnailPickerDelegate
    
    func thumbnailPicker(_ picker: ThumbnailPickerViewController, didSelectThumbnail image: UIImage) {
        picker.dismiss(animated: true)
        self.content.thumbnailURL = image.save(temporary: false)
        self.thumbnailImageView.image = image
    }

    // MARK: - VideoTrimmerDelegate

    func videoTrimmer(_ videoTrimmer: VideoTrimmerViewController, didFinishEditing output: AVURLAsset) {
        videoTrimmer.dismiss(animated: true)
        let oldDuration = self.content.duration
        self.content.assets = [output]
        self.updateContent()
        self.mergeAndUpload()
        Logging.log("Video Trimmed", ["TrimDuration": oldDuration - self.content.duration, "Result": "Success"])
    }

    func videoTrimmerDidCancel(_ videoTrimmer: VideoTrimmerViewController) {
        videoTrimmer.dismiss(animated: true)
        Logging.log("Video Trimmed", ["Result": "Cancelled"])
    }

    // MARK: - VideoViewDelegate

    func videoViewDidReachEnd(_ view: VideoView) {
        view.play()
    }

    // MARK: - Private

    private let cheerView = CheerView()
    private let imagePicker = UIImagePickerController()

    private var anywhereTapRecognizer: UITapGestureRecognizer!
    private var appendVideoAsIntro = true
    private var didPublish = false
    private var doubleTapProtection = false
    private var shareURL: URL!
    private var statusIndicatorView: StatusIndicatorView!
    private var videoView: VideoView!
    private var webController: SFSafariViewController?

    // these are triggered when the user explicitly turns toggles off
    private var facebookToggledOff = false
    private var reactionCamToggledOff = false
    private var saveToggledOff = false
    private var searchView: SearchView!
    private var igtvToggledOff = false
    private var instagramToggledOff = false
    private var tumblrToggledOff = false
    private var twitterToggledOff = false
    private var youTubeToggledOff = false

    @objc private dynamic func anywhereTapped() {
        guard self.titleTextView.isFirstResponder else {
            return
        }
        self.content.title = self.getTitle()
        self.titleTextView.resignFirstResponder()
    }

    private func finish() {
        self.hideLoading()

        if let request = self.content.request {
            // Put user back in request context if this was a request.
            TabBarController.select(tab: .requests, source: "Share")
            TabBarController.select(request: request, source: "Share")
            return
        }

        guard let content = self.content.persisted else {
            // Put user in their own profile if content hasn't been created yet.
            TabBarController.select(tab: .profile, source: "Share")
            return
        }

        // Take the user to the content page of the video that the user reacted
        // to, or the content page of the video itself if it wasn't a reaction.
        let relatedContent = self.content.related?.content
        TabBarController.select(tab: .search, source: "Share")
        TabBarController.select(
            originalContent: relatedContent ?? content,
            inject: relatedContent == nil ? nil : content,
            tab: OriginalContentViewController.Tab.recent,
            suggestSimilarCreators: true,
            animated: false,
            source: "Upload")
    }

    private func finishOnMain() {
        DispatchQueue.main.async {
            self.finish()
        }
    }

    private func generateShareCopy(content: ContentInfo) -> String? {
        guard let url = content.webURL?.absoluteString else {
            return nil
        }
        if let title = content.title {
            return title + " " + url
        } else {
            return url
        }
    }

    private func getTitle() -> String? {
        guard
            let value = self.titleTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
            else { return nil }
        return value == placeholder ? nil : value.replacingOccurrences(of: "\n", with: " ")
    }

    private func handleApplicationActiveStateChanged(active: Bool) {
        if active {
            // Resume playback of any playing review video.
            self.videoView.play()
        }
    }

    private func hideLoading() {
        self.statusIndicatorView.hide()
        self.view.isUserInteractionEnabled = true
    }
    
    @objc private dynamic func keyboardEvent(notification: NSNotification) {
        self.view.layoutIfNeeded()
        let info = notification.userInfo!
        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationCurve(UIViewAnimationCurve(rawValue: (info[UIKeyboardAnimationCurveUserInfoKey] as! NSNumber).intValue)!)
        UIView.setAnimationDuration((info[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue)
        UIView.setAnimationBeginsFromCurrentState(true)
        self.view.layoutIfNeeded()
        UIView.commitAnimations()
    }
    
    private func mergeAndUpload() {
        self.statusIndicatorView.showLoading()
        self.content.merge { _ in
            self.statusIndicatorView.hide()
            self.content.upload()
        }
    }

    private func shareToIGTV(completion: @escaping () -> ()) {
        guard let asset = self.content.mergedAsset else {
            completion()
            return
        }

        MediaManager.save(asset: asset, source: "Share Instagram") { localId in
            guard let id = localId else {
                Logging.danger("Review View Controller Instagram Error", ["Error": "SaveFailed"])
                completion()
                return
            }
            UIPasteboard.general.string = (self.content.title ?? "") + " on @reaction.cam"
            let alert = UIAlertController(title: "1. Tap into your IGTV channel\n2. Tap ➕ button to upload\n3. Tag @reaction.cam 🔖", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Got it 🙏", style: .cancel) { _ in
                guard UIApplication.shared.canOpenURL(URL(string: "igtv://")!) else {
                    Logging.log("Review View Controller", ["Action": "IGTV Download"])
                    let url = URL(string: "https://itunes.apple.com/us/app/igtv/id1394351700?mt=8")!
                    UIApplication.shared.open(url)
                    return
                }
                UIApplication.shared.open(URL(string: "igtv://library?LocalIdentifier=\(id)")!, options: [:], completionHandler: nil)
                Logging.info("Review Share Link Success", ["Destination": "IGTV", "Duration": asset.duration.seconds])
                completion()
            })
            self.present(alert, animated: true)
        }
    }

    private func shareToInstagram(completion: @escaping () -> ()) {
        guard let asset = self.content.mergedAsset else {
            completion()
            return
        }
        self.makeTeaser(asset: asset) { asset in
            self.statusIndicatorView.hide()
            MediaManager.save(asset: asset, source: "Share Instagram") { localId in
                guard let id = localId else {
                    Logging.danger("Review View Controller Instagram Error", ["Error": "SaveFailed"])
                    completion()
                    return
                }
                UIPasteboard.general.string = (self.content.title ?? "") + " on @reaction.cam"
                let alert = UIAlertController(title: "Paste your caption and tag @reaction.cam 🔖", message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Got it 🙏", style: .cancel) { _ in
                    UIApplication.shared.open(URL(string: "instagram://library?LocalIdentifier=\(id)")!, options: [:], completionHandler: nil)
                    Logging.info("Review Share Link Success", ["Destination": "Instagram", "Duration": asset.duration.seconds])
                    completion()
                })
                self.present(alert, animated: true)
            }
        }
    }
    
    private func makeTeaser(asset: AVURLAsset, maxDuration: TimeInterval = 15, completion: @escaping (AVURLAsset) -> ()) {
        // TODO Move this to a central place
        
        // Must be run on main thread!
        guard asset.url.isFileURL else {
            return
        }
        let duration = asset.duration
        guard duration.seconds > maxDuration else {
            completion(asset)
            return
        }
        // Create a montage of 2.5 sec clips
        let segmentDuration = 2.5
        let segments = Int(maxDuration / segmentDuration)
        let segmentInterval = duration.seconds / Double(segments - 1)
        var intervals = [1.0]
        intervals.append(contentsOf: (1..<segments-1).map { segmentInterval * Double($0) })
        intervals.append(segmentInterval * Double(segments-1) - segmentDuration)
        let trimPoints: [(CMTime, CMTime)] = intervals.map {
            (CMTime(seconds: $0,
                    preferredTimescale: duration.timescale),
             CMTime(seconds: $0 + segmentDuration,
                    preferredTimescale: duration.timescale))
        }
        AssetEditor.trim(asset: asset, to: trimPoints) {
            guard let trimmedAsset = $0 else {
                return
            }
            DispatchQueue.main.async { completion(trimmedAsset) }
        }
    }
    
    private func showShareLink(sourceView: UIView) {
        var copy = self.shareURL.absoluteString
        if let title = self.content.title, !title.isEmpty {
            copy = title + " " + copy
        }

        let share = UIActivityViewController(activityItems: [DynamicActivityItem(copy)], applicationActivities: nil)
        share.completionWithItemsHandler = { activity, success, _, error in
            guard success else {
                if let error = error {
                    Logging.warning("Review Share Link Action", [
                        "Result": "Error",
                        "Error": error.localizedDescription,
                        "Destination": "\(activity?.rawValue ?? "Other") (Link)"])
                } else {
                    Logging.debug("Review Share Link Action", [
                        "Result": "Cancel",
                        "Destination": "\(activity?.rawValue ?? "Other") (Link)"])
                }
                return
            }
            Logging.info("Review Share Link Action", [
                "Result": "Share",
                "Destination": "\(activity?.rawValue ?? "Other") (Link)"])
        }
        share.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
        share.configurePopover(sourceView: sourceView)
        self.present(share, animated: true)
    }

    private func showTrimmer(source: String) {
        let asset = self.content.assets[0]
        Logging.log("Video Trimmer Shown", ["Duration": asset.duration.seconds, "Source": source])
        guard let trimmer = Bundle.main.loadNibNamed("VideoTrimmerViewController", owner: nil, options: nil)?.first as? VideoTrimmerViewController else {
            return
        }
        trimmer.delegate = self
        trimmer.load(asset: asset)
        self.present(trimmer, animated: true)
    }

    private func showVideoError(message: String = "Something went wrong. Please try again with a different video.", title: String = "Oops! 😅") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addCancel(title: "OK")
        self.present(alert, animated: true)
    }

    private func updateContent() {
        self.videoView?.loadVideo(url: self.content.mergedAsset?.url ?? self.content.assets[0].url, force: true)
        self.videoView?.play()
    }

    private func updateTitle() {
        if let title = self.content.title {
            self.titleTextView.text = title
        } else if let relatedTitle = self.content.related?.content?.title {
            if relatedTitle.contains("REACTION.CAM") {
                self.titleTextView.text = relatedTitle
            } else {
                self.titleTextView.text = "\(relatedTitle) REACTION.CAM"
            }
        } else if case .recording = self.content.type {
            self.titleTextView.text = "\(Date().weekDay) #vlog"
        }
    }

    private func handleServiceConnected(service: String, code: Int) {
        self.webController?.dismiss(animated: true) {
            self.webController = nil
        }
        switch service {
        case "youtube":
            self.autopostYouTubeSwitch.isEnabled = true
            switch code {
            case 200:
                self.autopostYouTubeSwitch.isOn = true
                SettingsManager.autopostYouTube = true
                let alert = UIAlertController(
                    title: "YouTube Connected",
                    message: "Videos may take a couple of minutes to show up on your YouTube channel.",
                    preferredStyle: .alert)
                alert.addCancel(title: "Got it!")
                self.present(alert, animated: true)
            case 409:
                self.autopostYouTubeSwitch.isOn = false
                SettingsManager.autopostYouTube = false
                Logging.warning("YouTube Error", ["Error": "Already connected by another account"])
                let alert = UIAlertController(
                    title: "Uh-oh!",
                    message: "That YouTube account has already been connected to another reaction.cam account. Please reach out to us at yo@reaction.cam or by tapping Help below for assistance.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Help", style: .default) { _ in
                    HelpViewController.showHelp(presenter: self)
                })
                alert.addCancel(title: "Back")
                self.present(alert, animated: true)
            default:
                self.autopostYouTubeSwitch.isOn = false
                SettingsManager.autopostYouTube = false
            }
        default:
            break
        }
    }

    @objc private dynamic func facebookAutopostTapped() {
        guard autopostFacebookSwitch.isEnabled else {
            return
        }
        self.autopostFacebookSwitch.setOn(!self.autopostFacebookSwitch.isOn, animated: true)
        self.facebookAutopostToggled(self.autopostFacebookSwitch)
    }

    @objc private dynamic func igtvAutopostTapped() {
        guard autopostIGTVSwitch.isEnabled else {
            return
        }
        self.autopostIGTVSwitch.setOn(!self.autopostIGTVSwitch.isOn, animated: true)
        self.igtvAutopostToggled(self.autopostIGTVSwitch)
    }

    @objc private dynamic func instagramAutopostTapped() {
        guard autopostInstagramSwitch.isEnabled else {
            return
        }
        self.autopostInstagramSwitch.setOn(!self.autopostInstagramSwitch.isOn, animated: true)
        self.instagramAutopostToggled(self.autopostInstagramSwitch)
    }

    @objc private dynamic func reactionCamAutopostTapped() {
        guard autopostReactionCamSwitch.isEnabled else {
            return
        }
        self.autopostReactionCamSwitch.setOn(!self.autopostReactionCamSwitch.isOn, animated: true)
        self.reactionCamAutopostToggled(self.autopostReactionCamSwitch)
    }

    @objc private dynamic func tumblrAutopostTapped() {
        guard autopostTumblrSwitch.isEnabled else {
            return
        }
        self.autopostTumblrSwitch.setOn(!self.autopostTumblrSwitch.isOn, animated: true)
        self.tumblrAutopostToggled(self.autopostTumblrSwitch)
    }

    @objc private dynamic func twitterAutopostTapped() {
        guard autopostTwitterSwitch.isEnabled else {
            return
        }
        self.autopostTwitterSwitch.setOn(!self.autopostTwitterSwitch.isOn, animated: true)
        self.twitterAutopostToggled(self.autopostTwitterSwitch)
    }

    @objc private dynamic func youTubeAutopostTapped() {
        guard autopostYouTubeSwitch.isEnabled else {
            return
        }
        self.autopostYouTubeSwitch.setOn(!self.autopostYouTubeSwitch.isOn, animated: true)
        self.youTubeAutopostToggled(self.autopostYouTubeSwitch)
    }

    private func youTubeConnect() {
        self.autopostYouTubeSwitch.isEnabled = false
        let vc = SFSafariViewController(url: SettingsManager.youTubeAuthURL)
        self.webController = vc
        vc.delegate = self
        self.present(vc, animated: true) {}
    }
}
