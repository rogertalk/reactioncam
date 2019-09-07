import Alamofire
import AlamofireImage
import AVKit
import UIKit
import XLActionController

fileprivate let COMMENT_DURATION: Int = 8

protocol ContentCellDelegate: class {
    func contentCellDidEnterText(_ cell: ContentCell)
    func contentCellDidLeaveText(_ cell: ContentCell)
    func contentCellShowRepost(_ cell: ContentCell)
    func contentCellShowRequestReaction(_ cell: ContentCell)
    func contentCellShowReshare(_ cell: ContentCell)
    func contentCellShowSaveVideo(_ cell: ContentCell)
    func contentCellWasDeleted(_ cell: ContentCell)
    func contentCellMoveNext(_ cell: ContentCell, showLoader: Bool)
}

class ContentCell: UITableViewCell, UITextViewDelegate, ThumbnailPickerDelegate, VideoViewDelegate {

    weak var alert: UIViewController?
    var reaction: Content!

    @IBOutlet weak var actionsStackView: PassThroughStackView!
    @IBOutlet weak var backgroundImageView: UIImageView!
    @IBOutlet weak var badgesContainerView: UIView!
    @IBOutlet weak var fastForwardButton: BadgeButton!
    @IBOutlet weak var featuredBadgeLabel: UILabel!
    @IBOutlet weak var metadataStackView: PassThroughStackView!
    @IBOutlet weak var metadataBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var optionsButton: UIButton!
    @IBOutlet weak var playerContainerView: UIView!
    @IBOutlet weak var reactButton: UIButton!
    @IBOutlet weak var reactionsContainerView: UIView!
    @IBOutlet weak var reactionsCountLabel: UILabel!
    @IBOutlet weak var relatedContentButton: UIButton!
    @IBOutlet weak var repostButton: BadgeButton!
    @IBOutlet weak var repostBadgeContainerView: UIView!
    @IBOutlet weak var saveVideoButton: BadgeButton!
    @IBOutlet weak var rewardsContainerView: UIView!
    @IBOutlet weak var subscribeButton: UIButton!
    @IBOutlet weak var subscribeCTA: UILabel!
    @IBOutlet weak var titleLabel: TagLabel!
    @IBOutlet weak var usernameButton: UIButton!
    @IBOutlet weak var profilePictureButton: UIButton!
    @IBOutlet weak var verifiedBadgeImageView: UIImageView!
    @IBOutlet weak var videoView: VideoView!
    @IBOutlet weak var viewsContainerView: UIView!
    @IBOutlet weak var viewsLabel: UILabel!
    @IBOutlet weak var votesContainerView: UIView!
    @IBOutlet weak var votesIconLabel: UILabel!
    @IBOutlet weak var votesLabel: UILabel!
    @IBOutlet weak var bottomActionsConstraint: NSLayoutConstraint!

    @IBOutlet weak var textFieldContainerView: UIView!
    @IBOutlet weak var textField: UITextView!
    @IBOutlet weak var textFieldPlaceholderLabel: UILabel!
    @IBOutlet weak var textContainerView: PassThroughView!
    @IBOutlet weak var sendTextButton: UIButton!


    // Subscribe Upsell
    @IBOutlet weak var subscribeUpsellCopyLabel: UILabel!
    @IBOutlet weak var subscribeUpsellImageView: UIImageView!
    @IBOutlet weak var subscribeUpsellUsernameLabel: UILabel!
    @IBOutlet weak var subscribeUpsellView: UIVisualEffectView!

    weak var delegate: ContentCellDelegate?
    weak var presenter: UIViewController?

    private var didShowSubscribeUpsell = false
    private(set) var isInTextMode = false
    var isInHomeFeed = false
    
    var bottomPadding: CGFloat = 0.0 {
        didSet {
            self.bottomActionsConstraint.constant = self.bottomPadding
        }
    }
    
    var shouldShowSubscribeButton: Bool {
        return !FollowService.instance.isFollowing(self.reaction.creator) && !self.reaction.creator.isCurrentUser
    }

    var shouldShowSubscribeCTA: Bool {
        guard let bonusRemaining = BackendClient.api.session?.bonusBalance else {
            return false
        }
        return bonusRemaining > 0 && self.shouldShowSubscribeButton
    }

    func refresh() {
        self.statusIndicatorView = StatusIndicatorView.create(container: self.presenter!.view!)

        self.bottomPadding = self.isInHomeFeed ? 50 : 8
        self.subscribeButton.isHidden = !self.shouldShowSubscribeButton
        if let bonusRemaining = BackendClient.api.session?.bonusBalance, self.shouldShowSubscribeCTA {
            self.subscribeCTA.alpha = 1
            self.subscribeCTA.text = "\(bonusRemaining) FREE COINS remaining\nSubscribe to earn one"
            self.subscribeCTA.isHidden = false
            UIView.animate(withDuration: 0.5, delay: 3, options: [], animations: {
                self.subscribeCTA.alpha = 0
            }, completion: { _ in })
        } else {
            self.subscribeCTA.isHidden = true
        }
        self.sendTextButton.isHidden = true
        if let url = self.reaction.thumbnailURL {
            self.backgroundImageView.isHidden = false
            let r = URLRequest(url: url)
            ImageDownloader.default.download(r) {
                guard let image = $0.result.value else {
                    return
                }
                if image.size.width > image.size.height {
                    let rotatedImage = UIImage(cgImage: image.cgImage!, scale: 0, orientation: .right)
                    self.backgroundImageView.image = rotatedImage
                } else {
                    self.backgroundImageView.image = image
                }
            }
        }

        if let related = self.reaction.relatedTo {
            if let thumbURL = related.thumbnailURL {
                self.relatedContentButton.af_setImageBiased(for: .normal, url: thumbURL, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
                self.relatedContentButton.imageView?.contentMode = .scaleAspectFill
            } else {
                self.relatedContentButton.af_cancelImageRequest(for: .normal)
                self.relatedContentButton.setImage(#imageLiteral(resourceName: "relatedContent"), for: .normal)
            }
            self.relatedContentButton.isHidden = false
        } else {
            self.relatedContentButton.af_cancelImageRequest(for: .normal)
            self.relatedContentButton.isHidden = true
        }
        if let imageURL = self.reaction.creator.imageURL {
            self.profilePictureButton.af_setImage(for: .normal, url: imageURL, placeholderImage: #imageLiteral(resourceName: "single"))
        } else {
            self.profilePictureButton.af_cancelImageRequest(for: .normal)
            self.profilePictureButton.setImage(#imageLiteral(resourceName: "single"), for: .normal)
        }
        self.reactButton.isHidden = Recorder.instance.composer == nil

        self.usernameButton.setTitleWithoutAnimation(self.reaction.creator.username)
        self.usernameButton.titleLabel!.adjustsFontSizeToFitWidth = true
        self.verifiedBadgeImageView.isHidden = !self.reaction.creator.isVerified
        if !self.reaction.isFlagged, let videoURL = self.reaction.videoURL {
            self.videoView.loadVideo(url: videoURL)
        } else {
            self.videoView.clearVideo()
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        self.updateTitle()
        self.textFieldContainerView.isHidden = self.reaction.creator.isCurrentUser
        // TODO views in the app are deprecated, remove all together
        self.viewsContainerView.isHidden = true
        let views = self.reaction.views
        self.viewsLabel.text = "👀 \(formatter.string(from: NSNumber(value: views))!)"
        if self.reaction.tags.contains("repost") {
            self.repostBadgeContainerView.alpha = 1.0
            self.repostBadgeContainerView.isHidden = false
        } else {
            self.repostBadgeContainerView.isHidden = true
        }
        if self.reaction.tags.contains("featured") {
            self.featuredBadgeLabel.alpha = 1.0
            self.featuredBadgeLabel.isHidden = false
        } else if self.reaction.tags.contains("exfeatured") {
            self.featuredBadgeLabel.alpha = 0.4
            self.featuredBadgeLabel.isHidden = false
        } else {
            self.featuredBadgeLabel.isHidden = true
        }
        if self.reaction.relatedCount > 0 {
            self.reactionsCountLabel.text = self.reaction.relatedCount.countLabelShort
            self.reactionsContainerView.isHidden = false
        } else {
            self.reactionsContainerView.isHidden = true
        }
        self.updateVotes()
        self.updateSubscribeUpsell()
    }

    // MARK: - UITableViewCell

    override func awakeFromNib() {
        super.awakeFromNib()

        self.textField.delegate = self
        self.textFieldPlaceholderLabel.setSoftShadow()
        self.textField.tintColor = .uiYellow
        self.sendTextButton.setSoftShadow()

        self.videoView.delegate = self

        self.votesContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ContentCell.handleUpVoteTapped)))
        self.reactionsContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ContentCell.handleReactionsTapped)))
        self.rewardsContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ContentCell.handleRewardsTapped)))

        self.profilePictureButton.imageView?.contentMode = .scaleAspectFill
        self.profilePictureButton.setSoftShadow()
        self.usernameButton.setSoftShadow()
        self.optionsButton.setSoftShadow()
        self.subscribeButton.setSoftShadow()
        self.subscribeCTA.setSoftShadow()
        self.subscribeUpsellView.setSoftShadow()
        self.titleLabel.setSoftShadow()

        self.bottomPadding = self.isInHomeFeed ? 50 : 8
        self.tapGesture = UITapGestureRecognizer(target: self, action: #selector(ContentCell.handleTap))
        self.tapGesture.isEnabled = false
        self.contentView.addGestureRecognizer(self.tapGesture)

        // TODO: DO THIS ELSEWHERE
        NotificationCenter.default.addObserver(self, selector: #selector(ContentCell.keyboardEvent), name: .UIKeyboardWillChangeFrame, object: nil)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.subscribeButton.isHidden = false
        self.subscribeCTA.isHidden = true
        self.backgroundImageView.image = #imageLiteral(resourceName: "relatedContent")
        self.metadataStackView.alpha = 1
        self.textField.text = ""
        self.textFieldPlaceholderLabel.isHidden = false
        self.actionsStackView.isHidden = false
        self.metadataStackView.isHidden = false
        self.optionsButton.isHidden = false
        self.usernameButton.setTitle(nil, for: .normal)
        self.didShowSubscribeUpsell = false
        self.subscribeUpsellView.isHidden = true
        self.subscribeUpsellCopyLabel.text = SettingsManager.defaultBio
        self.subscribeUpsellImageView.image = #imageLiteral(resourceName: "single")
        self.subscribeUpsellUsernameLabel.text = "username"
        self.titleLabel.text = ""
        self.titleLabel.isHidden = true
        self.verifiedBadgeImageView.isHidden = true
        self.videoView.clearVideo()
        self.videoView.layer.removeAllAnimations()
        self.videoView.alpha = 1
        // self.localVotes = 0
        self.tipTimer?.fire()
        self.tipTimer = nil
    }

    // MARK: - Actions

    @IBAction func fastForwardTapped(_ sender: Any) {
        Logging.log("Content Options", ["Action": "Forward", "OwnProfile": self.reaction.creator.isCurrentUser])
        self.videoView.skipForward(seconds: 10)
        self.fastForwardButton.pulse()
    }
    
    @IBAction func optionsButtonTapped(_ sender: UIButton) {
        guard let presenter = self.presenter, let reaction = self.reaction else {
            return
        }
        let sheet = ActionSheetController()
        if let related = reaction.relatedTo, let title = related.title {
            var t = title
            if t.count > 20 {
                t = "\(t.prefix(20))…"
            }
            sheet.addAction(Action("Reaction to: \(t)", style: .default) { _ in
                Logging.log("Content Options", ["Action": "Open Related Content", "OwnProfile": reaction.creator.isCurrentUser])
                TabBarController.select(originalContent: related, source: "Content Options")
            })
        }
        if reaction.creator.isCurrentUser {
            sheet.addAction(Action("📌 Pin to Channel", style: .default, handler: { _ in
                Logging.log("Content Options", ["Action": "Pin", "OwnProfile": true])
                // TODO: Show loader.
                Intent.pin(content: reaction).perform(BackendClient.api) {
                    guard $0.successful else {
                        // TODO: Show error.
                        return
                    }
                }
            }))
        }
        sheet.addAction(Action("🔁 Repost", style: .default, handler: { _ in
            Logging.log("Content Options", ["Action": "Repost", "OwnProfile": reaction.creator.isCurrentUser])
            self.delegate?.contentCellShowRepost(self)
        }))
        sheet.addAction(Action("Share", style: .default, handler: { _ in
            Logging.log("Content Options", ["Action": "Share", "OwnProfile": reaction.creator.isCurrentUser])
            self.delegate?.contentCellShowReshare(self)
        }))
        sheet.addAction(Action("Copy Link", style: .default) { _ in
            Logging.log("Content Options", ["Action": "Copy Link", "OwnProfile": reaction.creator.isCurrentUser])
            if let url = reaction.webURL {
                UIPasteboard.general.string = url.absoluteString
                self.statusIndicatorView.showConfirmation(title: "Link Copied! 🔗")
                var copy = url.absoluteString
                if let title = reaction.title, !title.isEmpty {
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
                        "Duration": reaction.duration,
                        "Type": "ReactionLink"])
                }
                share.configurePopover(sourceView: sender)
                self.alert = share
                presenter.present(share, animated: true)
            } else {
                self.delegate?.contentCellShowReshare(self)
            }

        })
        sheet.addAction(Action("Request Reaction", style: .default, handler: { _ in
            Logging.log("Content Options", ["Action": "Request Reaction", "OwnProfile": reaction.creator.isCurrentUser])
            self.delegate?.contentCellShowRequestReaction(self)
        }))
        if reaction.creator.isCurrentUser {
            sheet.addAction(Action("Save to Camera Roll", style: .default) { _ in
                Logging.log("Content Edit Options", ["Action": "Save to Camera Roll"])
                self.delegate?.contentCellShowSaveVideo(self)
            })
            sheet.addAction(Action("Edit…", style: .default, handler: { _ in
                Logging.log("Content Options", ["Action": "Edit"])
                self.showEdit()
            }))
        } else {
            sheet.addAction(Action("Report Abuse", style: .destructive) { _ in
                Logging.log("Content Options", ["Action": "Report Abuse"])
                let alert = UIAlertController(
                    title: "Report Abuse",
                    message: "Continuing will report this video and user to the reaction.cam team and hide the video for you.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Report @\(reaction.creator.username)", style: .destructive) { _ in
                    Logging.danger("Report Abuse", ["Action": "Report", "ContentId": reaction.id])
                    self.videoView.alpha = 1
                    reaction.flag()
                    self.refresh()
                    self.delegate?.contentCellWasDeleted(self)
                })
                alert.addCancel() {
                    Logging.log("Report Abuse", ["Action": "Cancel"])
                    self.videoView.alpha = 1
                    self.videoView.play()
                }
                self.videoView.pause(showUI: false)
                self.videoView.alpha = 0.2
                self.alert = alert
                presenter.present(alert, animated: true)
            })
        }
        sheet.addCancel() {
            Logging.log("Content Options", ["Action": "Cancel"])
        }
        sheet.configurePopover(sourceView: sender)
        self.alert = sheet
        presenter.present(sheet, animated: true)
    }

    @IBAction func profilePictureButtonTapped(_ sender: Any) {
        Logging.log("Content Cell Element", ["Action": "Open Profile (Picture Button)"])
        TabBarController.select(account: self.reaction.creator)
    }

    @IBAction func reactTapped(_ sender: Any) {
        Logging.log("Content Cell Element", ["Action": "React"])
        guard let url = reaction.videoURL else {
            return
        }
        TabBarController.showCreate(url: url, ref: reaction.ref, relevantUsername: reaction.creator.username,
                                    source: "Content Cell React Action")
    }

    @IBAction func relatedButtonTapped(_ sender: UIButton) {
        Logging.log("Content Cell Element", ["Action": "Open Related Content (Button)"])
        guard let related = self.reaction.relatedTo else {
            return
        }
        TabBarController.select(originalContent: related, source: "Content Related Button")
    }

    @IBAction func saveVideoTapped(_ sender: Any) {
        Logging.log("Content Cell Element", ["Action": "Save Video (Button)"])
        self.delegate?.contentCellShowSaveVideo(self)
    }

    @IBAction func sendTextTapped(_ sender: Any) {
        guard let text = self.textField.text, !text.isEmpty else {
            self.textFieldContainerView.pulse()
            return
        }
        self.sendText(text: self.textField.text)
        self.textField.text = ""
        self.textField.endEditing(true)
    }

    @IBAction func repostButtonTapped(_ sender: Any) {
        Logging.log("Content Cell Element", ["Action": "Repost Video", "OwnProfile": self.reaction.creator.isCurrentUser])
        self.delegate?.contentCellShowRepost(self)
    }

    @IBAction func subscribeTapped(_ sender: UIButton) {
        Logging.log("Content Cell Element", ["Action": "Subscribe"])
        self.subscribe()
    }

    @IBAction func subscribeUpsellTapped(_ sender: Any) {
        Logging.log("Content Cell Element", ["Action": "Subscribe Upsell Subscribe"])
        self.subscribe()
        self.subscribeUpsellView.hideAnimated()
    }

    @IBAction func subscribeUpsellLaterTapped(_ sender: Any) {
        Logging.log("Content Cell Element", ["Action": "Subscribe Upsell Later"])
        self.subscribeUpsellView.hideAnimated()
    }

    @IBAction func usernameButtonTapped(_ sender: UIButton) {
        Logging.log("Content Cell Element", ["Action": "Open Profile"])
        TabBarController.select(account: self.reaction.creator)
    }

    // MARK: - UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text == "\n" else {
            return true
        }
        self.sendText(text: textView.text)
        textView.text = ""
        self.textField.endEditing(true)
        return false
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        self.playerContainerView.isUserInteractionEnabled = false
        self.videoView.pause(showUI: true)
        self.textContainerView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        self.tapGesture.isEnabled = true
        self.isInTextMode = true
        if let text = self.textField.text, !text.isEmpty {
            self.sendTextButton.isHidden = false
        } else {
            self.sendTextButton.isHidden = true
        }
        self.actionsStackView.isHidden = true
        self.metadataStackView.isHidden = true
        self.optionsButton.isHidden = true
        self.subscribeButton.isHidden = true
        self.subscribeCTA.isHidden = true
        self.subscribeUpsellView.isHidden = true
        self.delegate?.contentCellDidEnterText(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        if let text = textView.text, !text.isEmpty {
            self.textFieldPlaceholderLabel.isHidden = true
            self.sendTextButton.isHidden = false
        } else {
            self.textFieldPlaceholderLabel.isHidden = false
            self.sendTextButton.isHidden = true
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        self.playerContainerView.isUserInteractionEnabled = true
        self.videoView.play()
        self.textContainerView.backgroundColor = .clear
        self.tapGesture.isEnabled = false
        self.textFieldPlaceholderLabel.isHidden = false
        self.sendTextButton.isHidden = true
        self.actionsStackView.isHidden = false
        self.metadataStackView.isHidden = false
        self.optionsButton.isHidden = false
        self.subscribeButton.isHidden = !self.shouldShowSubscribeButton
        self.subscribeCTA.isHidden = !self.shouldShowSubscribeCTA
        self.isInTextMode = false
        self.delegate?.contentCellDidLeaveText(self)
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return self.ensureLoggedIn(self)
    }

    func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        guard let text = textView.text, !text.isEmpty, let presenter = self.presenter else {
            return true
        }
        let alert = UIAlertController(title: "Are you sure?",
                                      message: "Do you want to discard your message?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in
            Logging.log("Content Cell Element", ["Action": "Cancel Comment"])
            textView.text = ""
            self.textViewDidChange(textView)
            textView.resignFirstResponder()
        })
        alert.addCancel(title: "Keep")
        self.alert = alert
        presenter.present(alert, animated: true)
        return false
    }

    // MARK: - ThumbnailPickerDelegate
    
    func thumbnailPicker(_ picker: ThumbnailPickerViewController, didSelectThumbnail image: UIImage) {
        picker.dismiss(animated: true)
        
        guard let imageData = UIImageJPEGRepresentation(image, 0.7)
            else {
                return
        }

        Intent.updateContentThumbnail(contentId: self.reaction.id, thumbnail: .jpeg(imageData)).perform(BackendClient.api) {
            guard $0.successful else {
                let alert = UIAlertController(title: "Oops! 😅", message: "Something went wrong. Please try again.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.presenter?.present(alert, animated: true)
                return
            }
            if let data = $0.data, let content = Content(data: data) {
                ContentService.instance.contentUpdated.emit(content)
            }
            self.statusIndicatorView.showConfirmation()
        }
    }

    // MARK: - VideoViewDelegate

    var videoViewControlsFrame: CGRect? {
        let maxY = Int(self.metadataStackView.superview!.frame.minY + self.metadataStackView.superview!.superview!.frame.minY)
        if self.videoView.naturalSize.isLandscape {
            return CGRect(x: 8, y: 68, width: 60, height: maxY - 76)
        } else {
            let maxX = Int(self.actionsStackView.superview!.frame.minX + self.actionsStackView.frame.minX)
            return CGRect(x: 8, y: maxY - 68, width: maxX - 16, height: 60)
        }
    }

    func videoViewDidLoad(_ view: VideoView) {
        self.showUI()
    }

    func videoView(_ view: VideoView, offsetDidChangeTo offset: Double) {

        // SHow subscribe upsell 10 seconds before video finishes
        if let duration = self.videoView.videoDuration,
            offset >= duration - 10,
            !self.didShowSubscribeUpsell {
            self.showSubscribeUpsell()
        }
    }

    func videoView(_ view: VideoView, requestShowUI: Bool) {
        requestShowUI ? self.showUI() : self.hideUI()
    }

    func videoViewDidPause(_ view: VideoView) {
        self.showUI()
    }

    func videoViewDidPlay(_ view: VideoView) {
        ContentService.instance.reportView(id: self.reaction.id)
    }

    func videoViewDidReachEnd(_ view: VideoView) {
        if let duration = view.videoDuration {
            Logging.debug("Content Playback Event", ["Event": "Finish", "PlaybackDuration": duration])
        }
        if let alert = self.alert, alert.isViewLoaded == true && alert.view.window != nil {
            self.videoView.play()
        } else {
            self.delegate?.contentCellMoveNext(self, showLoader: false)
        }
    }

    // MARK: - Private

    // private var localVotes = 0
    private var statusIndicatorView: StatusIndicatorView!
    private var tapGesture: UITapGestureRecognizer!
    private var tipTimer: Timer?

    @objc private dynamic func handleTap() {
        guard self.textField.isFirstResponder else {
            return
        }
        Logging.log("Content Cell Element", ["Action": "Cancel Comment"])
        self.textField.endEditing(false)
    }

    @objc private dynamic func handleReactionsTapped() {
        Logging.log("Content Cell Element", ["Action": "Reactions Tapped"])
        self.reactionsContainerView.pulse()
        TabBarController.select(originalContent: self.reaction, source: "Content Reactions Button")
    }

    @objc private dynamic func handleRewardsTapped() {
        Logging.log("Content Cell Element", ["Action": "Rewards Tapped"])
        self.rewardsContainerView.pulse()
        self.videoView.pause(showUI: true)
        TabBarController.showRewards(for: self.reaction.creator)
    }
    
    @objc private dynamic func handleUpVoteTapped() {
        Logging.log("Vote Tapped", ["FirstVote": !self.reaction.voted])

        self.votesContainerView.pulse()
        self.reaction.vote()
        //self.localVotes += 1
        self.updateVotes()
        
        // Pool tips and send in batches
//        let total = (self.tipTimer?.userInfo as? Int ?? 0) + 1
//        self.tipTimer?.invalidate()
//        self.tipTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(ContentCell.sendTip), userInfo: total, repeats: false)

        self.showSubscribeUpsell()

        // Shoot the 💸 emoji up in a random direction.
        let voteLabel = UILabel()
        voteLabel.frame = self.convert(self.votesIconLabel.frame, from: self.votesContainerView).offsetBy(dx: 2, dy: 0)
        voteLabel.textAlignment = .center
        voteLabel.font = .systemFont(ofSize: 15)
        voteLabel.text = "👍"
        self.insertSubview(voteLabel, belowSubview: self.votesContainerView)
        UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseOut, animations: {
            voteLabel.transform = CGAffineTransform(scaleX: 2, y: 2).translatedBy(x: CGFloat(arc4random_uniform(60)) - 30, y: -85)
            voteLabel.alpha = 0
        }, completion: { _ in
            voteLabel.removeFromSuperview()
        })
    }

    @objc private dynamic func keyboardEvent(notification: NSNotification) {
        self.layoutIfNeeded()
        let info = notification.userInfo!
        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationCurve(UIViewAnimationCurve(rawValue: (info[UIKeyboardAnimationCurveUserInfoKey] as! NSNumber).intValue)!)
        UIView.setAnimationDuration((info[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue)
        UIView.setAnimationBeginsFromCurrentState(true)
        let frame = info[UIKeyboardFrameEndUserInfoKey] as! CGRect
        self.bottomActionsConstraint.constant = max(self.frame.height - frame.minY + 8, self.bottomPadding)
        self.layoutIfNeeded()
        UIView.commitAnimations()
    }

    private func ensureLoggedIn(_ cell: ContentCell) -> Bool {
        guard BackendClient.api.session?.hasBeenOnboarded == false, let presenter = self.presenter else {
            return true
        }
        let alert = UIAlertController(title: "Hold on...", message: "You need to sign up before you can send messages.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Sign up now! 😎", style: .default) { _ in
            Logging.log("Create Username Dialog Comment", ["Action": "Sign Up"])
            TabBarController.select(tab: .profile, source: "CommentSignUpCTA")
        })
        alert.addAction(UIAlertAction(title: "I'll do it later", style: .destructive) { _ in
            Logging.log("Create Username Dialog Comment", ["Action": "Later"])
        })
        self.alert = alert
        presenter.present(alert, animated: true)
        return false
    }

    private func sendText(text: String) {
        MessageService.instance.createThread(identifier: self.reaction.creator.username) { thread, error in
            guard let thread = thread, error == nil else {
                return
            }
            do {
                try thread.message(type: .text, text: text)
            } catch {
                return
            }
            self.statusIndicatorView.showConfirmation(title: "Sent")
            self.showSubscribeUpsell()
        }
    }

    @objc private dynamic func sendTip(timer: Timer) {
        guard let amount = timer.userInfo as? Int else {
            return
        }
        timer.invalidate()
        self.tipTimer = nil
        guard let session = BackendClient.api.session, session.balance > amount else {
            let alert = UIAlertController(title: "Oops!", message: "Not enough coins, try getting more!", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Get more", style: .default) { _ in
                Logging.log("Buy Coins Shown", ["Source": "ContentCell"])
                PaymentService.instance.showBuyCoins()
            })
            alert.addCancel()
            self.presenter?.present(alert, animated: true)
                Logging.log("Content Tip", [
                    "Value": String(amount),
                    "Result": "NotEnough"])
            return
        }
        
        let alert = UIAlertController(title: "Sent \(amount) coins!", message: "Thanks for your support 😊", preferredStyle: .alert)
        alert.addCancel(title: "OK")
        self.presenter?.present(alert, animated: true)
        
        let intent = Intent.pay(
            identifier: String(self.reaction.creator.id),
            amount: amount,
            comment: "Tip for reaction: \(self.reaction.title ?? "Not available")")
        intent.perform(BackendClient.api)
        Logging.log("Content Tip", [
            "Value": String(amount),
            "Result": "Success"])
        self.showSubscribeUpsell()
    }

    private func showEdit() {
        guard let presenter = self.presenter, let reaction = self.reaction else {
            return
        }
        let sheet = ActionSheetController(title: "Edit Video")
        sheet.addAction(Action("Edit Title", style: .default, handler: { _ in
            Logging.log("Content Edit Options", ["Action": "Change Title"])
            let changeTitleAlert = UIAlertController(title: "Edit Title", message: nil, preferredStyle: .alert)
            changeTitleAlert.addTextField(configurationHandler: { textField in
                textField.keyboardAppearance = .dark
                textField.keyboardType = .default
                textField.isSecureTextEntry = false
                textField.placeholder = "title, #tags & @mentions ✍️"
                textField.text = reaction.title
                textField.returnKeyType = .done
            })
            changeTitleAlert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in
                guard let fields = changeTitleAlert.textFields, let title = fields[0].text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) else {
                    return
                }
                Intent.updateContent(contentId: reaction.id, tags: reaction.tags, title: title, thumbnail: nil).perform(BackendClient.api) {
                    guard $0.successful, let data = $0.data, let content = Content(data: data) else {
                        return
                    }
                    self.reaction = content
                    self.updateTitle()
                    ContentService.instance.loadFeaturedContent()
                    ContentService.instance.contentUpdated.emit(content)
                }
            })
            changeTitleAlert.addCancel(title: "Cancel")
            self.alert = changeTitleAlert
            presenter.present(changeTitleAlert, animated: true)
        }))
        sheet.addAction(Action("Change Cover", style: .default) { _ in
            Logging.log("Content Edit Options", ["Action": "Change Thumbnail"])
            guard let url = self.reaction.videoURL,
                let thumbnailPicker = Bundle.main.loadNibNamed("ThumbnailPickerViewController", owner: nil, options: nil)?.first as? ThumbnailPickerViewController else {
                    return
            }
            
            thumbnailPicker.load(asset: AVURLAsset(url: url))
            thumbnailPicker.delegate = self
            self.presenter?.present(thumbnailPicker, animated: true)
        })
        sheet.addAction(Action("Delete Video", style: .destructive, handler: { _ in
            Logging.log("Content Edit Options", ["Action": "Delete"])
            var message: String
            if self.reaction.votes > 0 {
                message = "You'll lose \(self.reaction.votes) likes"
            } else {
                message = "This will delete the video permanently."

            }
            let alert = UIAlertController(title: "Are you sure?", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Yes", style: .destructive) { _ in
                Logging.log("Content Edit Options", ["Action": "DeleteYes"])
                UIView.animate(withDuration: 1) {
                    self.videoView.alpha = 0
                }
                Intent.updateContent(contentId: reaction.id, tags: ["deleted"], title: reaction.title, thumbnail: nil).perform(BackendClient.api) { _ in
                    let alert = UIAlertController(title: "Video Deleted", message: "Your video has been deleted.", preferredStyle: .alert)
                    alert.addCancel(title: "OK") {
                        self.delegate?.contentCellWasDeleted(self)
                    }
                    self.alert = alert
                    presenter.present(alert, animated: true)
                }
            })
            alert.addCancel(title: "No") {
                Logging.log("Content Edit Options", ["Action": "DeleteNo"])
                self.videoView.alpha = 1
                self.videoView.play()
            }
            self.videoView.pause(showUI: false)
            self.alert = alert
            presenter.present(alert, animated: true)
        }))
        sheet.addCancel() {
            Logging.log("Content Edit Options", ["Action": "Cancel"])
        }
        sheet.configurePopover(sourceView: self.optionsButton)
        self.alert = sheet
        presenter.present(sheet, animated: true)
    }

    private func showSubscribeUpsell() {
        guard self.shouldShowSubscribeButton && !self.didShowSubscribeUpsell else {
            return
        }
        self.subscribeUpsellView.showAnimated()
        self.didShowSubscribeUpsell = true
    }
    
    private func showUI() {
        self.metadataStackView.showAnimated()
    }

    private func subscribe() {
        guard let presenter = self.presenter else {
            return
        }
        self.statusIndicatorView.showLoading()
        let accountId = self.reaction.creator.id
        let bonusEarned: Bool
        if let session = BackendClient.api.session, session.bonusBalance > 0 {
            bonusEarned = true
            // Simulate bonus on the session.
            BackendClient.api.updateAccountData(receivingBonus: 1)
        } else {
            bonusEarned = false
        }
        FollowService.instance.follow(ids: [accountId]) {
            guard $0 else {
                self.statusIndicatorView.hide()
                let alert = UIAlertController(title: "Connection Error 😬", message: "Please check your internet connection.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Settings", style: .default) { (_) in
                    UIApplication.shared.open(URL(string:UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: { (_) in
                    })
                })
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in })
                self.alert = alert
                presenter.present(alert, animated: true)
                return
            }
            self.statusIndicatorView.showConfirmation(title: bonusEarned ? "1 COIN EARNED" : nil)
            if self.reaction.creator.id == accountId {
                self.subscribeButton.isHidden = true
                self.subscribeCTA.isHidden = true
            }
        }
    }

    private func hideUI() {
        UIView.animate(withDuration: 0.2, delay: 0, options: .allowUserInteraction, animations: {
            self.metadataStackView.alpha = 0
        })
    }

    private func updateSubscribeUpsell() {
        guard self.shouldShowSubscribeButton else {
            return
        }
        self.subscribeUpsellUsernameLabel.text = self.reaction.creator.username
        if let imageURL = self.reaction.creator.imageURL {
            self.subscribeUpsellImageView.af_setImage(withURL: imageURL, placeholderImage: #imageLiteral(resourceName: "single"))
        } else {
            self.subscribeUpsellImageView.af_cancelImageRequest()
            self.subscribeUpsellImageView.image = #imageLiteral(resourceName: "single")
        }
        self.subscribeUpsellCopyLabel.text = SettingsManager.defaultBio
        let creatorId = self.reaction.creator.id
        Intent.getProfile(identifier: String(creatorId)).perform(BackendClient.api) {
            guard
                $0.successful,
                let data = $0.data,
                data["id"] as? Int64 == creatorId,
                let properties = data["properties"] as? DataType,
                let bio = (properties["bio"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !bio.isEmpty
                else { return }
            self.subscribeUpsellCopyLabel.text = bio
        }
    }

    private func updateTitle() {
        guard let title = self.reaction.title, !title.isEmpty else {
            self.titleLabel.isHidden = true
            return
        }
        self.titleLabel.text = title
        self.titleLabel.isHidden = false
    }

    private func updateVotes() {
        let votes = self.reaction.votes + (self.reaction.voted ? 1 : 0) //self.localVotes
        self.votesLabel.isHidden = votes == 0
        self.votesLabel.text = votes.countLabelShort
        self.votesIconLabel.textColor = self.reaction.voted ? UIColor.uiBlue : .white
        self.votesLabel.textColor = self.reaction.voted ? UIColor.uiBlue : .white
    }
}
