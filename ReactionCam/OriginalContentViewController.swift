import Alamofire
import AlamofireImage
import UIKit
import XLActionController

class OriginalContentViewController:
    UIViewController,
    ContentCollectionDelegate {

    enum Tab: Int { case top = 0, comments, recent }

    @IBOutlet weak var actionsContainer: UIView!
    @IBOutlet weak var actionsTop: NSLayoutConstraint!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var contentCollectionView: ContentCollectionView!
    @IBOutlet weak var creatorLabel: UILabel!
    @IBOutlet weak var creatorImageView: UIImageView!
    @IBOutlet weak var creatorStackView: UIStackView!
    @IBOutlet weak var fullTitleLabel: UILabel!
    @IBOutlet weak var headerHeight: NSLayoutConstraint!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var metadataContainer: UIView!
    @IBOutlet weak var optionsButton: UIButton!
    @IBOutlet weak var reactButton: HighlightButton!
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var verifiedBadgeImage: UIImageView!

    var content: ContentInfo!
    var source = "Unknown"

    var injectedContent: Content? {
        didSet {
            self.updateInjectedContent()
            self.contentCollectionView?.reloadData()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    var preselectedTab: Tab = .top
    var suggestSimilarCreators = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.backButton.setHeavyShadow()
        self.fullTitleLabel.setHeavyShadow()
        self.optionsButton.setHeavyShadow()
        self.titleLabel.setHeavyShadow()

        self.headerView.setHeavyShadow()

        let title = self.content.title ?? ""
        self.fullTitleLabel.text = title
        self.titleLabel.text = title
        self.creatorStackView.isHidden = true

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        let reactionCount = formatter.string(from: NSNumber(value: self.content.relatedCount))!
        let reactionNoun = self.content.relatedCount == 1 ? "Reaction" : "Reactions"
        self.contentCollectionView.headerTitle = "\(reactionCount) \(reactionNoun)"

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.contentCollectionView.contentInset =
            UIEdgeInsets(top: self.defaultHeaderHeight + self.actionsHeight + 8,
                         left: 0,
                         bottom: 0,
                         right: 0)

        self.updateThumb()
        self.creatorLabel.text = ""

        Intent.getContent(id: self.content.id).perform(BackendClient.api) {
            guard $0.successful, let content = $0.data.flatMap(Content.init(data:)) else {
                return
            }

            self.decoratedContent = content
            if !content.creator.isAnonymousUser {
                self.creatorLabel.text = content.creator.username
                if let url = content.creator.imageURL {
                    self.creatorImageView.af_setImage(withURL: url, placeholderImage: #imageLiteral(resourceName: "single"))
                } else {
                    self.creatorImageView.image = #imageLiteral(resourceName: "single")
                }
                self.verifiedBadgeImage.isHidden = !content.creator.isVerified
                self.creatorStackView.isHidden = false
            }
        }

        // Don't show REACT button to Old Device Users
        self.reactButton.isHidden = Recorder.instance.composer == nil

        ContentService.instance.contentCreated.addListener(self, method: OriginalContentViewController.handleContentCreated)

        self.creatorStackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(OriginalContentViewController.creatorTapped)))

        self.loadRelatedContent(refresh: false)
        self.contentCollectionView.contentCollectionDelegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.suggestSimilarCreators {
            self.suggestSimilarCreators = false
            // Present after a short delay
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
                DispatchQueue.main.async {
                    let similarCreators = self.related
                        .filter { $0.creator.id != BackendClient.api.session?.id }
                        .prefix(5)
                        .map { $0.creator }
                    guard !similarCreators.isEmpty, let vc = Bundle.main.loadNibNamed("SimilarCreatorsViewController", owner: nil, options: nil)?.first as? SimilarCreatorsViewController else {
                        return
                    }
                    vc.similarCreators = similarCreators
                    self.navigationController?.pushViewControllerModal(vc)
                }
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.uploads = UploadService.instance.jobs.values.filter { $0.isVisible }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Setting uploads to an empty list will prevent updating the UI while it's hidden.
        self.uploads = []

        self.view.endEditing(true)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @IBAction func backTapped(_ sender: Any) {
        Logging.debug("Original Content", ["Action": "Back"])
        self.navigationController?.popViewController(animated: true)
    }

    @IBAction func creatorTapped(_ sender: UIButton) {
        guard let creator = self.decoratedContent?.creator else {
            return
        }
        TabBarController.select(account: creator)
    }
    
    @IBAction func fullTitleTapped(_ sender: UITapGestureRecognizer) {
        Logging.log("Original Content", ["Action": "React (Title)"])
        self.goToReact(source: "Original Title Tapped (\(self.source))")
    }

    @IBAction func optionsButtonTapped(_ sender: UIButton) {
        let sheet = ActionSheetController()
        if let creator = self.decoratedContent?.creator, !creator.isAnonymousUser {
            sheet.addAction(Action("@\(creator.username)'s channel", style: .default) { _ in
                Logging.log("Original Content Options", ["Action": "Open Profile"])
                TabBarController.select(account: creator)
            })
        }
        if let related = self.decoratedContent?.relatedTo, let title = related.title {
            var t = title
            if t.count > 25 {
                t = "\(t.prefix(25))…"
            }
            sheet.addAction(Action("👁‍🗨 \(t)", style: .default) { _ in
                Logging.log("Original Content Options", ["Action": "Open Related Content"])
                TabBarController.select(originalContent: related, source: "Original Of Original")
            })
        }
        if let url = self.content.webURL {
            sheet.addAction(Action("Copy Video Link", style: .default) { _ in
                Logging.log("Original Content", ["Action": "Copy Video Link"])
                UIPasteboard.general.string = url.absoluteString
                self.statusIndicatorView.showConfirmation(title: "Link Copied! 🔗")
                var copy = url.absoluteString
                if let title = self.content.title, !title.isEmpty {
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
                        "Duration": self.content.duration,
                        "Type": "ReactionLink"])
                }
                share.configurePopover(sourceView: sender)
                self.present(share, animated: true)
            })
        }

        if self.content.creatorId == BackendClient.api.session?.id {
            sheet.addAction(Action("Delete", style: .destructive, handler: { _ in
                Logging.log("Original Content Options", ["Action": "Delete"])
                var message: String
                if self.content.votes > 0 {
                    message = "You'll lose \(self.content.views) \(self.content.views == 1 ? "VIEW" : "VIEWS") and \(self.content.votes) likes"
                } else {
                    message = "This will delete the video permanently."

                }
                let alert = UIAlertController(title: "Are you sure?", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Yes", style: .destructive) { _ in
                    Logging.log("Original Content Options", ["Action": "DeleteYes"])
                    Intent.updateContent(contentId: self.content.id, tags: ["deleted"], title: self.content.title, thumbnail: nil).perform(BackendClient.api) { _ in
                        let alert = UIAlertController(title: "Video Deleted", message: "Your video has been deleted.", preferredStyle: .alert)
                        alert.addCancel(title: "OK") {
                            TabBarController.select(tab: .profile, source: "Original Content")
                            self.navigationController?.popToRootViewController(animated: true)
                        }
                        self.present(alert, animated: true)
                    }
                })
                alert.addCancel(title: "No") {
                    Logging.log("Original Content Options", ["Action": "DeleteNo"])
                }
                self.present(alert, animated: true)
            }))
        } else {
            sheet.addAction(Action("Report Abuse", style: .destructive) { _ in
                Logging.log("Original Content Options", ["Action": "Report Abuse"])
                let alert = UIAlertController(
                    title: "Report Abuse",
                    message: "Continuing will report this video and user to the reaction.cam team and hide the video for you.",
                    preferredStyle: .alert)
                let reportButtonLabel: String
                if let creator = self.decoratedContent?.creator, !creator.isAnonymousUser {
                    reportButtonLabel = "Report @\(creator.username)"
                } else {
                    reportButtonLabel = "Report"
                }
                alert.addAction(UIAlertAction(title: reportButtonLabel, style: .destructive) { _ in
                    Logging.danger("Report Abuse (Original Content)", [
                        "Action": "Report",
                        "ContentId": self.content.id])
                    self.content.flag()
                    self.navigationController?.popViewController(animated: true)
                })
                alert.addCancel() {
                    Logging.log("Report Abuse (Original Content)", ["Action": "Cancel"])
                }
                self.present(alert, animated: true)
            })
        }
        sheet.addCancel() {
            Logging.log("Original Content Options", ["Action": "Cancel"])
        }
        sheet.configurePopover(sourceView: sender)
        self.present(sheet, animated: true)
    }

    @IBAction func reactTapped(_ sender: HighlightButton) {
        Logging.log("Original Content", ["Action": "React"])
        self.goToReact(source: "Original React Button (\(self.source))")
    }

    @IBAction func requestReactionTapped(_ sender: HighlightButton) {
        Logging.log("Original Content", ["Action": "Request Reaction"])
        guard let content = self.content else {
            return
        }
        guard self.checkDeletedStatus() else {
            return
        }
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
                    "Type": "ReactionLink"])
            }
            share.configurePopover(sourceView: sender)
            self.present(share, animated: true)
        } else {
            guard let share = Bundle.main.loadNibNamed("ShareViewController", owner: nil, options: nil)?.first as? ShareViewController else {
                return
            }
            share.mode = self.content.creatorId == BackendClient.api.session?.id ? .reshareOwn(content: self.content) : .request(content: self.content)
            self.navigationController?.pushViewController(share, animated: true)        }
    }

    @IBAction func titleTapped(_ sender: UITapGestureRecognizer) {
        self.contentCollectionView.scrollRectToVisible(CGRect(x: 0, y: 0, width: 1, height: 1), animated: true)
    }

    // MARK: - ContentCollectionDelegate
    
    func contentCollection(_ contentCollectionView: UICollectionView, didScrollTo offset: CGPoint) {
        let refreshOffset = contentCollectionView.contentSize.height - contentCollectionView.bounds.height * 1.1
        if offset.y > refreshOffset && self.cursor != nil && !self.isLoadingContent {
            self.loadRelatedContent(refresh: false)
        }
        let y: CGFloat
        if #available(iOS 11.0, *) {
            y = offset.y + contentCollectionView.adjustedContentInset.top
        } else {
            y = offset.y + contentCollectionView.contentInset.top
        }
        self.actionsTop.constant = max(self.defaultHeaderHeight - y - 8, self.minHeaderHeight - self.actionsHeight - 8)
        self.headerHeight.constant = max(self.defaultHeaderHeight - y, self.minHeaderHeight)
        let alpha = min(max(y / self.minHeaderHeight * 2, 0), 1)
        self.metadataContainer.alpha = 1 - alpha
        self.titleLabel.alpha = alpha
        self.contentCollectionView.scrollIndicatorInsets = UIEdgeInsets(top: self.headerHeight.constant,
                                                                        left: 0, bottom: 0, right: 0)
    }

    func contentCollection(_ contentCollectionView: UICollectionView, didSelectUpload upload: UploadJob, at indexPath: IndexPath) {
        let source = "Upload Menu (OriginalContentViewController)"
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Save to Camera Roll", style: .default) { _ in
            UploadService.instance.save(assetFor: upload, source: source) { id in
                guard id != nil else { return }
                let alert = UIAlertController(
                    title: "Saved to Camera Roll",
                    message: "Your video has been saved.",
                    preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
            }
            contentCollectionView.deselectItem(at: indexPath, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            let alert = UIAlertController(
                title: "Are you sure?",
                message: "You will lose your video unless you save it first.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                UploadService.instance.cancel(jobId: upload.id)
                contentCollectionView.reloadData()
                contentCollectionView.deselectItem(at: indexPath, animated: false)
            })
            alert.addCancel {
                contentCollectionView.deselectItem(at: indexPath, animated: false)
            }
            self.present(alert, animated: true)
        })
        sheet.addCancel(title: "Back") {
            contentCollectionView.deselectItem(at: indexPath, animated: true)
        }
        sheet.configurePopover(sourceView: contentCollectionView.cellForItem(at: indexPath) ?? contentCollectionView)
        self.present(sheet, animated: true)
    }
    
    // MARK: - Private

    private var minHeaderHeight: CGFloat {
        if #available(iOS 11.0, *) {
            return 104 + self.view.safeAreaInsets.top
        } else {
            return 124
        }
    }

    private var comments = [Comment]()
    private var cursor: String?
    private var decoratedContent: Content?
    private var didShowCreatedContent: Bool = false
    private var isLoadingContent = false
    private var statusIndicatorView: StatusIndicatorView!
    private var replyingTo: Comment?

    private var actionsHeight: CGFloat {
        return self.actionsContainer.bounds.height
    }

    private var defaultHeaderHeight: CGFloat {
        let screen = UIScreen.main.bounds
        let height = round(min(screen.width * 9 / 16, screen.height / 4))
        if #available(iOS 11.0, *) {
            return height + self.view.safeAreaInsets.top
        } else {
            return height
        }
    }

    private var related = [Content]() {
        didSet {
            self.contentCollectionView?.content = self.related
        }
    }
    
    private var uploads = [UploadJob]() {
        didSet {
            self.contentCollectionView?.uploads = self.uploads
        }
    }

    private func checkDeletedStatus() -> Bool {
        if self.content.tags.contains("deleted") {
            Logging.warning("Original Content Deleted Alert")
            let alert = UIAlertController(
                title: "Uh-oh!",
                message: "This video has been deleted by the creator and can’t be reacted to. 😬",
                preferredStyle: .alert)
            alert.addCancel(title: "Doh!")
            self.present(alert, animated: true)
            return false
        } else {
            return true
        }
    }

    private func goToReact(source: String) {
        if let url = self.content.originalURL {
            TabBarController.showCreate(url: url, source: source)
        } else if let videoURL = self.content.videoURL {
            guard self.checkDeletedStatus() else {
                return
            }
            if let creator = self.decoratedContent?.creator, !creator.isAnonymousUser {
                TabBarController.showCreate(url: videoURL, ref: self.content.ref, relevantUsername: creator.username, source: source)
            } else {
                TabBarController.showCreate(url: videoURL, ref: self.content.ref, source: source)
            }
        }
    }

    private func handleContentCreated(content: Content) {
        guard content.relatedTo?.id == self.content.id, content.tags.contains("reaction") else {
            return
        }
        self.injectedContent = content
    }

    @objc private dynamic func handleTap() {
        self.view.endEditing(true)
    }

    private func loadRelatedContent(refresh: Bool) {
        if refresh {
            self.cursor = nil
        }
        self.statusIndicatorView.showLoading()
        self.isLoadingContent = true
        ContentService.instance.getRelatedContentList(for: self.content, sortBy: "top", cursor: self.cursor) {
            self.isLoadingContent = false
            self.statusIndicatorView.hide()
            // Inject related info
            if refresh {
                self.related = $0 ?? [Content]()
            } else if let results = $0 {
                self.related.append(contentsOf: results)
            }
            self.cursor = $1
            self.updateInjectedContent()
            self.contentCollectionView.reloadData()
            if refresh {
                let insetTop: CGFloat
                if #available(iOS 11.0, *) {
                    insetTop = self.contentCollectionView.adjustedContentInset.top
                } else {
                    insetTop = self.contentCollectionView.contentInset.top
                }
                self.contentCollectionView.setContentOffset(CGPoint(x: 0, y: -insetTop), animated: true)
            }
        }
    }
    
    private func updateInjectedContent() {
        guard let content = self.injectedContent else {
            return
        }
        if let index = self.related.index(where: { $0.id == content.id }) {
            self.related.remove(at: index)
        }
        self.related.insert(content, at: 0)
    }

    private func updateThumb() {
        guard let thumbURL = self.content.thumbnailURL else {
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
