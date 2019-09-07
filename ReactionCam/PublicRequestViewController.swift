import Alamofire
import AlamofireImage
import SafariServices
import UIKit

class PublicRequestViewController: UIViewController,
    SFSafariViewControllerDelegate,
    UIGestureRecognizerDelegate,
    UITableViewDataSource,
    UITableViewDelegate
{
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var earningsView: UIStackView!
    @IBOutlet weak var earningsLabel: UILabel!
    @IBOutlet weak var fullSubtitleLabel: UILabel!
    @IBOutlet weak var fullTitleLabel: UILabel!
    @IBOutlet weak var headerHeight: NSLayoutConstraint!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var helpButton: UIButton!
    @IBOutlet weak var introRewardInfoLabel: UILabel!
    @IBOutlet weak var introRewardLabel: UILabel!
    @IBOutlet weak var introSubtitleLabel: UILabel!
    @IBOutlet weak var introTitleLabel: UILabel!
    @IBOutlet weak var introView: UIView!
    @IBOutlet weak var optionsButton: UIButton!
    @IBOutlet weak var reactionImage: UIImageView!
    @IBOutlet weak var reactionTitle: UILabel!
    @IBOutlet weak var reactOrPickView: UIStackView!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var rewardLabel: UILabel!
    @IBOutlet weak var rewardCoinImage: UIImageView!
    @IBOutlet weak var rulesView: UIStackView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var statusTitleLabel: UILabel!
    @IBOutlet weak var statusTextLabel: UILabel!
    @IBOutlet weak var step1AView: UIStackView!
    @IBOutlet weak var step1BView: UIStackView!
    @IBOutlet weak var step2AView: UIStackView!
    @IBOutlet weak var step2BTitleLabel: UILabel!
    @IBOutlet weak var step2BView: UIStackView!
    @IBOutlet weak var step3View: UIStackView!
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var youTubeImage: UIImageView!
    @IBOutlet weak var youTubePickerView: UIView!
    @IBOutlet weak var youTubePickerViewTable: UITableView!
    @IBOutlet weak var youTubeTitle: UILabel!

    var info: PublicContentRequestDetails!
    var source = "Unknown"

    func reloadData(callback: (() -> ())? = nil) {
        guard self.callbacks == nil else {
            if let cb = callback { self.callbacks!.append(cb) }
            return
        }
        if let cb = callback {
            self.callbacks = [cb]
        } else {
            self.callbacks = []
        }
        Intent.getPublicContentRequest(id: self.info.request.id).perform(BackendClient.api) {
            self.callbacks?.forEach { $0() }
            self.callbacks = nil
            guard
                $0.successful,
                let info = $0.data.flatMap(PublicContentRequestDetails.init(data:))
                else
            {
                let alert = UIAlertController(
                    title: "Uh oh!",
                    message: "We couldn’t load the details for this request. Make sure you’re connected to the internet and try again.",
                    preferredStyle: .alert)
                alert.addCancel(title: "OK") {
                    self.navigationController?.popViewController(animated: true)
                }
                self.present(alert, animated: true)
                return
            }
            self.info = info
            self.update()
        }
    }

    // MARK: - UIViewController

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLayoutSubviews() {
        let height = self.defaultHeaderHeight
        self.headerHeight.constant = height
        self.scrollView.contentInset.top = height
        self.scrollView.scrollIndicatorInsets.top = height
        if #available(iOS 11.0, *) {
            let safeAreaBottom = self.view.safeAreaInsets.bottom
            self.scrollView.contentInset.bottom = safeAreaBottom
            self.scrollView.scrollIndicatorInsets.bottom = safeAreaBottom
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.backButton.setHeavyShadow()
        self.headerView.setHeavyShadow()
        self.fullSubtitleLabel.setHeavyShadow()
        self.fullTitleLabel.setHeavyShadow()
        self.optionsButton.setHeavyShadow()
        self.rewardLabel.setHeavyShadow()
        self.titleLabel.setHeavyShadow()
        self.youTubePickerViewTable.setHeavyShadow()

        self.update()
        if
            !SettingsManager.didSeePublicRequestIntro,
            !self.info.request.isClosed,
            let reward = self.info.request.reward,
            reward > 0
        {
            self.introView.isHidden = false
        } else {
            self.introView.isHidden = true
        }

        if self.info.status == .loading {
            // Load up the full details.
            self.reloadData()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        if self.isMovingToParentViewController {
            BackendClient.api.sessionChanged.addListener(self, method: PublicRequestViewController.handleSessionChanged)
            ContentService.instance.serviceConnected.addListener(self, method: PublicRequestViewController.handleServiceConnected)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        if self.isMovingFromParentViewController {
            BackendClient.api.sessionChanged.removeListener(self)
            ContentService.instance.serviceConnected.removeListener(self)
        }
    }

    // MARK: - Actions

    @IBAction func backTapped(_ sender: UIButton) {
        Logging.debug("Public Request", ["Action": "Back"])
        self.navigationController?.popViewController(animated: true)
    }

    @IBAction func closeIntroTapped(_ sender: UIButton) {
        SettingsManager.didSeePublicRequestIntro = true
        UIView.animate(withDuration: 0.3,
                       animations: { self.introView.alpha = 0 },
                       completion: { _ in self.introView.isHidden = true })
    }

    @IBAction func connectYouTubeTapped(_ sender: UIButton) {
        Logging.debug("Public Request", ["Action": "Connect YouTube"])
        let vc = SFSafariViewController(url: SettingsManager.youTubeAuthURL)
        self.safari = vc
        vc.delegate = self
        self.present(vc, animated: true)
    }

    @IBAction func helpTapped(_ sender: Any) {
        Logging.debug("Public Request", ["Action": "Help", "Status": self.info.status.rawValue])
        HelpViewController.showHelp(presenter: self)
    }

    @IBAction func optionsTapped(_ sender: UIButton) {
        Logging.debug("Public Request", ["Action": "Options"])
    }

    @IBAction func pickVideoTapped(_ sender: UIButton) {
        Logging.debug("Public Request", ["Action": "Pick Video"])
        self.youTubePickerVideos = nil
        self.youTubePickerVisible = true
        self.updateSteps()
        ContentService.instance.getYouTubeVideos {
            guard self.youTubePickerVisible else {
                // The picker UI was hidden while we were loading, so don't do anything.
                return
            }
            guard !$0.isEmpty else {
                let alert = UIAlertController(
                    title: "No videos found",
                    message: "We could not see any YouTube videos on your channel. Confirm that you’ve connected the right channel.",
                    preferredStyle: .alert)
                alert.addCancel {
                    self.youTubePickerVisible = false
                    self.updateSteps()
                }
                self.present(alert, animated: true)
                return
            }
            self.youTubePickerVideos = $0
            self.updateSteps()
            let alert = UIAlertController(
                title: "Pick a reaction video to\n“\(self.info.request.title)”",
                message: "Other videos will not be approved.",
                preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
        }
    }

    @IBAction func reactTapped(_ sender: UIButton) {
        Logging.debug("Public Request", ["Action": "React"])
        TabBarController.showCreate(request: self.info.request,
                                    source: "Public Request Details")
    }

    @IBAction func resetTapped(_ sender: UIButton) {
        let alert = UIAlertController(
            title: "Are you sure?",
            message: "This will reset your submission to this sponsored request.\n\n(Your video will NOT be deleted from your channel.)",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { _ in
            self.info = PublicContentRequestDetails(request: self.info.request)
            self.update()
            let intent = Intent.resetPublicContentRequestEntry(requestId: self.info.request.id)
            intent.perform(BackendClient.api) { _ in
                self.reloadData()
            }
        })
        alert.addCancel()
        self.present(alert, animated: true)
    }

    @IBAction func rewardTapped(_ sender: UITapGestureRecognizer) {
        guard let reward = self.info.request.reward, reward > 0 else {
            return
        }
        self.introView.alpha = 0
        self.introView.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.introView.alpha = 1
        }
    }

    @IBAction func shareYouTubeTapped(_ sender: UIButton) {
        guard let url = self.info.entry?.youTubeURL else {
            return
        }
        Logging.debug("Public Request", ["Action": "Share YouTube Link"])
        // Generate the text that will be shared.
        let copy: String
        if let title = self.info.request.content.title {
            copy = "Reaction to \(title) - \(url.absoluteString)"
        } else {
            copy = url.absoluteString
        }
        // Pop up a share sheet.
        let share = UIActivityViewController(activityItems: [DynamicActivityItem(copy)], applicationActivities: nil)
        share.completionWithItemsHandler = { activity, success, _, error in
            guard success else {
                if let error = error {
                    Logging.warning("Public Request Share Error", [
                        "Description": error.localizedDescription,
                        "Destination": activity?.rawValue ?? "Other"])
                } else {
                    Logging.debug("Public Request Share Action", [
                        "Action": "Cancel",
                        "Destination": activity?.rawValue ?? "Other"])
                }
                return
            }
            Logging.info("Public Request Share Success", [
                "Destination": activity?.rawValue ?? "Other"])
        }
        share.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
        share.configurePopover(sourceView: sender)
        self.present(share, animated: true)
    }

    @IBAction func youTubePickerViewTapped(_ sender: UITapGestureRecognizer) {
        self.youTubePickerVisible = false
        self.updateSteps()
    }

    // MARK: - SFSafariViewControllerDelegate

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        self.safari = nil
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return touch.view == self.youTubePickerView
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.youTubePickerVideos != nil ? 1 : 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "YouTubeVideo", for: indexPath) as! YouTubeVideoCell
            cell.video = self.youTubePickerVideos?[indexPath.row]
            return cell
        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section == 0, let videos = self.youTubePickerVideos else {
            return 0
        }
        return videos.count
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch indexPath.section {
        case 0:
            guard let video = self.youTubePickerVideos?[indexPath.row] else {
                break
            }
            guard video.status != .private else {
                let alert = UIAlertController(
                    title: "Private YouTube video",
                    message: "That video is private. If you wish to use this video, please change its privacy to public on your YouTube channel, then try again.",
                    preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                break
            }
            self.youTubePickerVideos = nil
            self.updateSteps()
            ContentService.instance.submitPublicRequestEntry(self.info.request.id, youTubeId: video.id, source: "Public Request Details") { successful, message in
                guard successful else {
                    let alert = UIAlertController(
                        title: "Could not submit video",
                        message: "\(message ?? "Something went wrong. Please try again").\n\nIf the issue persists, message the @reaction.cam account.",
                        preferredStyle: .alert)
                    alert.addCancel(title: "OK") {
                        self.youTubePickerVisible = false
                        self.updateSteps()
                    }
                    self.present(alert, animated: true)
                    return
                }
                self.reloadData {
                    self.youTubePickerVisible = false
                }
            }
        default:
            break
        }
        return nil
    }

    // MARK: - Private

    private var callbacks: [() -> ()]?

    private var defaultHeaderHeight: CGFloat {
        let screen = UIScreen.main.bounds
        let height = round(min(screen.width * 9 / 16, screen.height / 4))
        if #available(iOS 11.0, *) {
            return height + self.view.safeAreaInsets.top
        } else {
            return height
        }
    }

    private var safari: SFSafariViewController?
    private var youTubePickerVideos: [YouTubeVideo]?
    private var youTubePickerVisible = false

    private func formatNumber(_ value: Int?) -> String {
        guard let value = value else {
            return "–"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "–"
    }

    private func handleServiceConnected(service: String, code: Int) {
        self.safari?.dismiss(animated: true) {
            self.safari = nil
        }
        self.updateSteps()
        switch service {
        case "youtube":
            SettingsManager.autopostYouTube = code == 200
            if code == 409 {
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
            }
        default:
            break
        }
    }

    private func handleSessionChanged() {
        self.updateSteps()
    }

    private func update() {
        self.fullSubtitleLabel.text = self.info.request.subtitle
        self.fullTitleLabel.text = self.info.request.title
        self.introSubtitleLabel.text = self.info.request.subtitle
        self.introTitleLabel.text = self.info.request.title
        self.titleLabel.text = self.info.request.title

        if let reward = self.info.request.reward {
            let rewardText = self.formatNumber(reward)
            self.introRewardInfoLabel.text = "This request has \(rewardText) Coins left that are still up for grabs."
            self.introRewardLabel.text = rewardText
            self.rewardLabel.text = rewardText
            self.rewardCoinImage.isHidden = false
            self.rewardLabel.isHidden = false
        } else {
            self.rewardCoinImage.isHidden = true
            self.rewardLabel.isHidden = true
        }

        self.updateThumb()
        self.updateSteps()
    }

    private func updateSteps() {
        // Hide views by default, and later unhide them depending on status.
        self.helpButton.isHidden = true
        self.step1AView.isHidden = true
        self.step1BView.isHidden = true
        self.step2AView.isHidden = true
        self.step2BView.isHidden = true
        self.step3View.isHidden = true
        self.earningsView.isHidden = true
        self.resetButton.isHidden = true
        self.rulesView.isHidden = true
        self.youTubePickerView.isHidden = true

        if self.info.status == .loading {
            self.activityIndicator.startAnimating()
        } else {
            self.activityIndicator.stopAnimating()
        }

        // Handle closed requests first.
        guard self.info.status != .closed else {
            self.statusTitleLabel.text = "Sponsored Request (Closed)"
            self.statusTextLabel.text = "This request is no longer taking any entries. Keep a lookout for other sponsored requests on the Requests tab!"
            return
        }

        if self.info.status == .loading && self.info.request.isClosed {
            // Don't show anything else until info is loaded if request is closed.
            return
        }

        // Check if step 1 is complete.
        guard let youTube = BackendClient.api.session?.youTubeChannel else {
            self.statusTitleLabel.text = "Sponsored Request"
            self.statusTextLabel.text = "React to it and receive Coins that can be exchanged for real money based on how many views your reaction video gets on YouTube."
            self.step1AView.isHidden = false
            return
        }

        // Step 1 complete.
        if let url = youTube.thumbURL {
            self.youTubeImage.af_setImage(withURL: url, placeholderImage: #imageLiteral(resourceName: "single"))
        } else {
            self.youTubeImage.image = #imageLiteral(resourceName: "single")
        }
        self.youTubeTitle.text = youTube.title
        self.step1BView.isHidden = false

        // Reaction video metadata (if available).
        if let url = self.self.info.reaction?.thumbnailURL {
            self.reactionImage.af_setImage(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
        } else {
            self.reactionImage.image =  #imageLiteral(resourceName: "relatedContent")
        }
        self.reactionTitle.text = self.self.info.reaction?.title

        // Earnings info (if available).
        self.earningsLabel.text = self.formatNumber(self.info.entry?.rewardEarned)

        // Check if step 2 is complete.
        switch self.info.status {
        case .loading:
            // We don't have the information loaded yet.
            self.statusTitleLabel.text = " "
            self.statusTextLabel.text = "\n"
        case .open:
            // Not complete. Show CTA to react or pick a video.
            self.step2AView.isHidden = false
            self.statusTitleLabel.text = "Sponsored Request"
            self.statusTextLabel.text = "React to it and receive Coins that can be exchanged for real money based on how many views your reaction video gets on YouTube."
            // Show YouTube picker if user clicked the "Pick Video" button.
            if self.youTubePickerVisible {
                self.reactOrPickView.isHidden = true
                if self.youTubePickerVideos != nil {
                    self.youTubePickerViewTable.reloadData()
                    self.youTubePickerView.isHidden = false
                } else {
                    self.activityIndicator.startAnimating()
                }
            } else {
                self.reactOrPickView.isHidden = false
                self.rulesView.isHidden = false
            }
        case .closed:
            // Already handled above.
            break
        case .pendingUpload:
            // An entry has been created, waiting for content to upload.
            self.statusTitleLabel.text = "Status: Pending Upload"
            self.statusTextLabel.text = "Your video is still being uploaded. Please check back later."
            self.helpButton.isHidden = false
            self.step2BView.isHidden = false
            self.step2BTitleLabel.text = "Step 2: Pending Upload"
            // TODO: We need to be able to remove the request reference in the upload first.
            //self.resetButton.setTitle("Abort and start over", for: .normal)
            //self.resetButton.isHidden = false
        case .pendingYouTube:
            // Content has been uploaded, waiting for YouTube video to become visible.
            self.statusTitleLabel.text = "Status: YouTube Processing"
            self.statusTextLabel.text = "Your video has been uploaded, and YouTube is processing it. Please check back later."
            self.helpButton.isHidden = false
            self.step2BView.isHidden = false
            self.step2BTitleLabel.text = "Step 2: YouTube Processing"
            // TODO: We need to be able to remove the request reference from the content first.
            //self.resetButton.setTitle("Abort and start over", for: .normal)
            //self.resetButton.isHidden = false
        case .pendingReview:
            // YouTube video detected, waiting for approval by staff.
            self.statusTitleLabel.text = "Status: Pending Approval ⏳"
            self.statusTextLabel.text = "Your video has been uploaded, and is waiting to be approved. Please check back later."
            self.step2BView.isHidden = false
            self.step2BTitleLabel.text = "Step 2: Pending Approval"
            self.rulesView.isHidden = false
            self.resetButton.setTitle("Take my video out of review", for: .normal)
            self.resetButton.isHidden = false
        case .active:
            // Entry has been approved and is earning rewards.
            self.statusTitleLabel.text = "Status: Active 🤑"
            self.statusTextLabel.text = "Your YouTube reaction video is earning Coins based on many views it gets on YouTube."
            self.step2BView.isHidden = false
            self.step2BTitleLabel.text = "Step 2: Done ✓"
            self.earningsView.isHidden = false
            self.step3View.isHidden = false
            self.resetButton.setTitle("Remove my entry", for: .normal)
            self.resetButton.isHidden = false
        case .denied:
            // Entry was denied in the review process.
            self.statusTitleLabel.text = "Status: Rejected ❌"
            if let reason = self.info.statusReason {
                self.statusTextLabel.text = reason
            } else {
                self.statusTextLabel.text = "Your video has been rejected as it didn't comply with the request’s rules."
            }
            self.helpButton.isHidden = false
            self.step2BView.isHidden = false
            self.step2BTitleLabel.text = "Step 2: Rejected ❌"
            self.rulesView.isHidden = false
            self.resetButton.setTitle("Remove my entry so I can try again", for: .normal)
            self.resetButton.isHidden = false
        case .inactive:
            // Entry has become inactive for some reason.
            self.statusTitleLabel.text = "Status: Inactive ⏸"
            if let reason = self.info.statusReason {
                self.statusTextLabel.text = reason
            } else {
                self.statusTextLabel.text = "There was a problem with your video."
            }
            self.helpButton.isHidden = false
            self.step2BView.isHidden = false
            self.step2BTitleLabel.text = "Step 2: Done ✓"
            self.earningsView.isHidden = false
            self.resetButton.setTitle("Remove my entry", for: .normal)
            self.resetButton.isHidden = false
        }
    }

    private func updateThumb() {
        guard let thumbURL = self.info.request.content.thumbnailURL else {
            return
        }
        ImageDownloader.default.download(URLRequest(url: thumbURL)) {
            guard let image = $0.result.value else {
                return
            }
            let height = self.defaultHeaderHeight
            let size = CGSize(width: round(height * 2.5), height: height)
            let imageRatio = image.size.width / image.size.height
            let canvasRatio = size.width / size.height
            let factor = imageRatio > canvasRatio ? size.height / image.size.height : size.width / image.size.width
            let scaledSize = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            let origin = CGPoint(x: (size.width - scaledSize.width) / 2, y: (size.height - scaledSize.height) / 2)
            UIGraphicsBeginImageContextWithOptions(size, true, 0)
            guard let context = UIGraphicsGetCurrentContext() else {
                return
            }
            defer { UIGraphicsEndImageContext() }
            context.interpolationQuality = .high
            image.draw(in: CGRect(origin: origin, size: scaledSize))
            guard let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                            colorComponents: [0, 0, 0, 0,
                                                              0, 0, 0, 1],
                                            locations: nil,
                                            count: 2)
                else { return }
            context.drawLinearGradient(gradient,
                                       start: .zero,
                                       end: CGPoint(x: 0, y: size.height + 1),
                                       options: [])
            guard let finalImage = UIGraphicsGetImageFromCurrentImageContext() else {
                return
            }
            self.thumbnailImageView.image = finalImage
        }
    }
}

class YouTubeVideoCell: UITableViewCell {
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var thumbView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!

    var video: YouTubeVideo? {
        didSet {
            self.update()
        }
    }

    // MARK: - UITableViewCell

    override func prepareForReuse() {
        super.prepareForReuse()
        self.thumbView.af_cancelImageRequest()
    }

    // MARK: - NSObject

    override func awakeFromNib() {
        super.awakeFromNib()
        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        self.backgroundView = backgroundView
        let highlightView = UIView()
        highlightView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        self.selectedBackgroundView = highlightView
    }

    // MARK: - Private

    private func update() {
        guard let video = self.video else { return }
        if let url = video.thumbURL {
            self.thumbView.af_setImage(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
        } else {
            self.thumbView.af_cancelImageRequest()
            self.thumbView.image = #imageLiteral(resourceName: "relatedContent")
        }
        self.titleLabel.text = video.title
        switch video.status {
        case .private:
            self.subtitleLabel.text = "Private ⚠️"
        case .public:
            self.subtitleLabel.text = "Public"
        case .unlisted:
            self.subtitleLabel.text = "Unlisted"
        }
    }
}
