import Alamofire
import AVFoundation
import UIKit

fileprivate let SECTION_FOLLOWING = 0
fileprivate let SECTION_FEATURED = 1
fileprivate let SECTION_RECENTS = 666 //Tentacion

class ContentViewController:
    UIViewController,
    UITableViewDelegate,
    UITableViewDataSource,
    ContentCellDelegate {

    enum ContentAction {
        case repost
    }

    var action: ContentAction?
    var contentOffset: Double?
    var contentTag: String?
    var contentTitle: String?
    var recentContent = [Content]()
    var presetContentId: Int64?

    @IBOutlet weak var backButton: CameraControlButton!
    @IBOutlet weak var blackScreenView: UIView!
    @IBOutlet weak var paginatingSpinner: UIActivityIndicatorView!
    @IBOutlet weak var featuredTable: UITableView!
    @IBOutlet weak var peopleButton: CameraControlButton!
    @IBOutlet weak var recentsTable: UITableView!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var subscriptionsTable: UITableView!
    @IBOutlet weak var tagVideosCTAView: UIView!
    @IBOutlet weak var titleLabel: UILabel!

    var isFrontPage: Bool {
        return self.tabBarController != nil
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.setupContentTable(tableView: self.recentsTable)

        self.backButton.setSoftShadow()
        self.peopleButton.setSoftShadow()
        self.segmentedControl.setHeavyShadow()
        self.titleLabel.setTinyShadow()
        
        if self.isFrontPage {
            self.peopleButton.isHidden = false

            // TODO remove segmented view controller all together
            self.segmentedControl.setTitleTextAttributes([NSAttributedStringKey.font: UIFont.systemFont(ofSize: 18, weight: .bold),
                                                          NSAttributedStringKey.underlineStyle : NSUnderlineStyle.styleNone.rawValue,
                                                          NSAttributedStringKey.foregroundColor: UIColor.white],
                                                         for: .normal)
            self.segmentedControl.setTitleTextAttributes([NSAttributedStringKey.font: UIFont.systemFont(ofSize: 18, weight: .bold),
                                         NSAttributedStringKey.underlineStyle : NSUnderlineStyle.styleThick.rawValue,
                                         NSAttributedStringKey.underlineColor: UIColor.uiYellow,
                                         NSAttributedStringKey.foregroundColor: UIColor.white],
                                        for: .selected)

            self.setupContentTable(tableView: self.subscriptionsTable)
            self.refreshSubsControl.tintColor = .white
            self.refreshSubsControl.addTarget(self, action: #selector(ContentViewController.handleRefreshSubscriptions), for: .valueChanged)
            self.subscriptionsTable.refreshControl = self.refreshSubsControl

            // TODO: Remove featured table
            self.setupContentTable(tableView: self.featuredTable)

            self.switchToContentList(SECTION_FOLLOWING)
            if !ContentService.instance.hasLoadedSubscriptionContent {
                self.statusIndicatorView.showLoading()
            }
            ContentService.instance.subscriptionContentChanged.addListener(self, method: ContentViewController.updateSubscriptionContent)
            ContentService.instance.subscriptionContentChanged.addListener(self, method: ContentViewController.updateFeaturedContent)
            AppDelegate.applicationActiveStateChanged.addListener(self, method: ContentViewController.handleApplicationActiveStateChanged)

            ContentService.instance.featuredContentChanged.addListener(self, method: ContentViewController.updateFeaturedContent)
            self.updateFeaturedContent()
        } else {
            self.backButton.isHidden = false
            self.selectedContentListIndex = SECTION_RECENTS
            self.featuredTable.isHidden = true
            self.subscriptionsTable.isHidden = true
            self.recentsTable.isHidden = false

            if let tag = self.contentTag {
                self.titleLabel.text = self.contentTitle ?? "#\(tag)"

                self.statusIndicatorView.showLoading()
                ContentService.instance.getContentList(tags: [tag, "reaction"], sortBy: "hot") { result, _ in
                    self.statusIndicatorView.hide()
                    guard let result = result else {
                        let alert = UIAlertController(title: "Rats! 🐀", message: "Something went wrong. Make sure you‘re online and try again.", preferredStyle: .alert)
                        alert.addCancel(title: "OK")
                        self.present(alert, animated: true)
                        return
                    }
                    guard !result.isEmpty else {
                        let alert = UIAlertController(title: "Hmm 😬", message: "There aren't any videos for this hashtag. Try making one!", preferredStyle: .alert)
                        alert.addCancel(title: "OK")
                        self.present(alert, animated: true)
                        return
                    }
                    self.recentContent = result
                    self.recentsTable.reloadData()
                    self.playVisibleVideoView()
                }
            }

            // Show the correct reaction, fetching it if necessary
            if let id = self.presetContentId {
                if self.recentContent.isEmpty {
                    self.statusIndicatorView.showLoading()
                    Intent.getContent(id: id).perform(BackendClient.api) {
                        self.statusIndicatorView.hide()
                        guard $0.successful, let data = $0.data, let reaction = Content(data: data) else {
                            let alert = UIAlertController(
                                title: "Uh-oh!",
                                message: "Looks like that video has been deleted 😬",
                                preferredStyle: .alert)
                            alert.addCancel(title: "OK") {
                                self.navigationController?.popViewController(animated: true)
                            }
                            self.present(alert, animated: true)
                            return
                        }
                        self.recentContent = [reaction]
                        self.recentsTable.reloadData()
                        self.playVisibleVideoView()
                    }
                } else if let index = self.recentContent.index(where: { $0.id == id }) {
                    DispatchQueue.main.async {
                        self.recentsTable.scrollToRow(at: IndexPath(row: index, section: 0), at: .top, animated: false)
                    }
                }
            }

            self.recentsTable.reloadData()
            self.playVisibleVideoView()
        }
        // TODO Remove all together
        self.segmentedControl.isHidden = true
        self.titleLabel.isHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.recentsTable.visibleCells.forEach {
            ($0 as? ContentCell)?.videoView.recapturePlayer()
        }
        self.subscriptionsTable.visibleCells.forEach {
            ($0 as? ContentCell)?.videoView.recapturePlayer()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.scrollRecentIfNeeded()

        // TODO there is probably a better way to do this
        let table = self.selectedReactionsTable
        if table.numberOfRows(inSection: 0) > 1 {
            UIView.animate(withDuration: 0.3, animations: {
                table.setContentOffset(CGPoint.init(x: 0, y: table.contentOffset.y + 40), animated: false)
            }) { _ in
                table.setContentOffset(CGPoint.init(x: 0, y: table.contentOffset.y - 40), animated: true)
            }
        }

        // Resume playback when user comes back.
        self.playVisibleVideoView()
        if self.action == .repost {
            self.action = nil
            guard
                self.view.window != nil,
                let indexPath = self.currentIndexPath,
                let cell = self.selectedReactionsTable.cellForRow(at: indexPath) as? ContentCell else
            {
                return
            }
            self.contentCellShowRepost(cell)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        VideoView.pauseAll()

        if self.selectedReactionsTable == self.recentsTable {
            SettingsManager.lastFeedView = Date()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(true)
        self.recentsTable.visibleCells.forEach {
            ($0 as? ContentCell)?.videoView.releasePlayer()
        }
        self.subscriptionsTable.visibleCells.forEach {
            ($0 as? ContentCell)?.videoView.releasePlayer()
        }
    }

    func scrollToTop() {
        let table = self.selectedReactionsTable
        guard table.numberOfRows(inSection: 0) > 0 else {
            return
        }
        let index = IndexPath(row: 0, section: 0)
        UIView.animate(withDuration: 0.3, animations: {
            table.scrollToRow(at: index, at: .top, animated: false)
        }) { _ in
            self.playVisibleVideoView()
        }
    }

    // MARK: - Actions

    @IBAction func addTapped(_ sender: Any) {
        VideoView.pauseAll(showUI: true)
        let tags = Bundle.main.loadNibNamed("TagsViewController", owner: nil, options: nil)?.first as! TagsViewController
        self.present(tags, animated: true)
        Logging.log("Add Section Tapped")
    }

    @IBAction func backTapped(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }

    @IBAction func findReactorsTapped(_ sender: Any) {
        Logging.log("Content View Action", ["Action": "Find Channels (Empty CTA)"])
        TabBarController.select(tab: .search, source: "Content")
    }

    @IBAction func inviteTapped(_ sender: UIButton) {
        Logging.log("Content View Action", ["Action": "Invite Friends (Empty CTA)"])
        let body = SettingsManager.shareChannelCopy(account: BackendClient.api.session)
        let vc = UIActivityViewController(activityItems: [DynamicActivityItem(body)], applicationActivities: nil)
        vc.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
        vc.configurePopover(sourceView: sender)
        self.present(vc, animated: true)
    }

    @IBAction func peopleButtonTapped(_ sender: Any) {
        Logging.log("Content View Action", ["Action": "My Subscriptions"])
        guard let session = BackendClient.api.session else {
            return
        }
        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "AccountList") as! AccountListViewController
        vc.type = .following(account: session)
        self.navigationController!.pushViewController(vc, animated: true)
    }

    @IBAction func segmentValueChanged(_ sender: UISegmentedControl) {
        self.switchToContentList(sender.selectedSegmentIndex)
    }

    // MARK: - Presenter

    func present(_ vc: UIViewController, completion: (() -> ())?) {
        self.present(vc, animated: true, completion: completion)
    }

    // MARK: - ContentCellDelegate

    func contentCellShowRepost(_ cell: ContentCell) {
        cell.videoView.pause(showUI: true)
        self.cacheVideo(url: cell.reaction.videoURL!) { asset in
            let content = PendingContent(assets: [asset])
            content.type = .repost(cell.reaction)
            content.title = "#repost @\(cell.reaction.creator.username): \(cell.reaction.title ?? "")"
            if let related = cell.reaction.relatedTo {
                content.related = RelatedContentEntry(content: related)
            }
            TabBarController.instance?.showReview(content: content, source: "Repost")
        }
    }

    func contentCellShowRequestReaction(_ cell: ContentCell) {
        guard
            let share = Bundle.main.loadNibNamed("ShareViewController", owner: nil, options: nil)?.first as? ShareViewController,
            let content = cell.reaction
            else { return }
        share.mode = .request(content: content)
        self.navigationController?.pushViewControllerModal(share)
    }

    func contentCellShowSaveVideo(_ cell: ContentCell) {
        cell.videoView.pause(showUI: true)
        self.cacheVideo(url: cell.reaction.videoURL!) { asset in
            MediaManager.save(asset: asset, source: "ContentCell", completion: { _ in
                self.statusIndicatorView.showConfirmation(title: "Saved to Camera Roll")
                Logging.info("Content View Export Success", [
                    "Destination": "Camera Roll (Video)",
                    "Duration": asset.duration.seconds])
            })
        }
    }

    func contentCellDidEnterText(_ cell: ContentCell) {
        self.backButton.isHidden = true
        self.peopleButton.isHidden = true
        self.recentsTable.isScrollEnabled = false
        self.subscriptionsTable.isScrollEnabled = false
        self.featuredTable.isScrollEnabled = false
    }

    func contentCellDidLeaveText(_ cell: ContentCell) {
        if self.isFrontPage {
            self.peopleButton.isHidden = false
        } else {
            self.backButton.isHidden = false
        }
        self.recentsTable.isScrollEnabled = true
        self.subscriptionsTable.isScrollEnabled = true
        self.featuredTable.isScrollEnabled = true
    }

    func contentCellShowReshare(_ cell: ContentCell) {
        guard
            let share = Bundle.main.loadNibNamed("ShareViewController", owner: nil, options: nil)?.first as? ShareViewController,
            let content = cell.reaction
            else { return }
        if content.creator.isCurrentUser {
            share.mode = .reshareOwn(content: content)
        } else {
            share.mode = .reshareOther(content: content)
        }
        self.navigationController?.pushViewControllerModal(share)
    }

    func contentCellWasDeleted(_ cell: ContentCell) {
        ContentService.instance.removeSubscriptionContent(id: cell.reaction.id)
    }

    func contentCellMoveNext(_ cell: ContentCell, showLoader: Bool = false) {
        let table = self.selectedReactionsTable

        let moveNext = {
            guard let indexPath = table.indexPath(for: cell), table.numberOfRows(inSection: indexPath.section) > indexPath.row + 1 else {
                return
            }
            let newIndex = IndexPath(row: indexPath.row + 1, section: indexPath.section)
            table.scrollToRow(at: newIndex, at: .top, animated: true)
            (table.cellForRow(at: newIndex) as? ContentCell)?.videoView.play()
        }

        if showLoader {
            self.statusIndicatorView.showLoading(title: "Tuning feed...", delay: 0)
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
                moveNext()
                self.statusIndicatorView.hide()
            }
        } else {
            moveNext()
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.selectedReactionsTable.isPagingEnabled = true
        self.selectedReactionsTable.frame = CGRect(origin: .zero, size: self.view.bounds.size)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.view.endEditing(true)
        guard let index = self.currentIndexPath?.row else {
            return
        }
        if index != self.lastContentIndex {
            self.lastContentIndex = index
            let view: String
            if self.isFrontPage {
                view = self.selectedSectionName
            } else {
                view = "SpecificContent"
            }
            Logging.debug("Swiped To Content", ["Index": index, "View": view])
        }

        self.selectedReactionsTable.isPagingEnabled = false
        self.selectedReactionsTable.frame = CGRect(origin: .zero, size: CGSize(width: self.view.bounds.width, height: self.view.bounds.height + 2))
        // Autoplay on-screen video.
        self.playVisibleVideoView()

        guard self.isFrontPage,
            self.selectedContentListIndex == SECTION_RECENTS, self.recentContent.count > 0 else {
            return
        }
        // Load more if we are 4 screen heights away from the end
        guard self.statusIndicatorView.isHidden &&
            !self.isPaginating &&
            scrollView.contentOffset.y >
            (scrollView.contentSize.height - scrollView.frame.size.height * 4) else {
                return
        }
        self.isPaginating = true
        ContentService.instance.loadRecentContent(refresh: false) { _ in
            self.isPaginating = false
        }
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    // MARK: UITableViewDataSource

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UIScreen.main.bounds.height
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        switch tableView {
        case self.subscriptionsTable:
            return 2
        default:
            return 1
        } 
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? self.getReactionsForTable(tableView).count : ContentService.instance.hasLoadedSubscriptionContent ? 1 : 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == self.subscriptionsTable && indexPath.section == 1 {
            return tableView.dequeueReusableCell(withIdentifier: "FollowMoreCell", for: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "ContentCell") as! ContentCell
        cell.isInHomeFeed = self.tabBarController != nil
        cell.reaction = self.getReactionsForTable(tableView)[indexPath.row]
        cell.presenter = self
        cell.delegate = self
        cell.refresh()
        return cell
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0.01
    }

    // MARK: - Private

    private var didTryShowSubs = false
    private var featuredContent = [Content]()
    private var importAlert: ConversationImportAlert?
    private var selectedContentListIndex: Int = 0
    private var subscriptionContent = [Content]()
    private var lastContentIndex = 0

    private let refreshSubsControl = UIRefreshControl()

    private var isPaginating = false {
        didSet {
            self.paginatingSpinner.isHidden = !self.isPaginating
        }
    }

    private func cacheVideo(url: URL, callback: @escaping (AVURLAsset) -> ()) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MediaCache")
        let localURL = caches.appendingPathComponent(url.lastPathComponent).appendingPathExtension("mp4")
        let request = Alamofire.download(url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil, to: {
            (_, _) -> (URL, DownloadRequest.DownloadOptions) in
            // Return the path on disk where the file should be stored.
            return (localURL, [])
        })
        self.blackScreenView.isHidden = false
        TabBarController.instance?.isHidden = true
        self.statusIndicatorView.showLoading(title: "Loading 0%")
        UIApplication.shared.isIdleTimerDisabled = true
        request.downloadProgress() { progress in
            DispatchQueue.main.async {
                self.statusIndicatorView.showLoading(title: "Loading \(Int(progress.fractionCompleted * 100))%")
            }
        }
        request.response() {
            self.blackScreenView.isHidden = true
            self.statusIndicatorView.hide()
            UIApplication.shared.isIdleTimerDisabled = false
            TabBarController.instance?.isHidden = false
            if let error = $0.error, (error as NSError).code != NSFileWriteFileExistsError {
                NSLog("Warning: Could not cache video \(error)")
                Logging.warning("Content Cell Error", [
                    "Error": error.localizedDescription])
                let alert = UIAlertController(title: "Oops!", message: "Download failed. Please try again later.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            let asset = AVURLAsset(url: localURL)
            callback(asset)
        }
    }

    private var currentIndexPath: IndexPath? {
        return self.selectedReactionsTable.indexPathForRow(at: selectedReactionsTable.contentOffset.applying(CGAffineTransform(translationX: 0, y: 20)))
    }

    private var selectedReactions: [Content] {
        return self.getReactionsForTable(self.selectedReactionsTable)
    }

    private var selectedReactionsTable: UITableView {
        guard self.isFrontPage else {
            return self.recentsTable
        }
        switch self.selectedContentListIndex {
        case SECTION_FOLLOWING:
            return self.subscriptionsTable
        case SECTION_FEATURED:
            return self.featuredTable
        default:
            return self.recentsTable
        }
    }

    private var selectedSectionName: String {
        let section: String
        let index = self.selectedContentListIndex
        switch index {
        case SECTION_FOLLOWING:
            section = "SUBSCRIBING"
        case SECTION_FEATURED:
            section = "#FEATURED"
        case SECTION_RECENTS:
            section = "RECENTS"
        default:
            section = "Unknown"
        }
        return section
    }

    private var statusIndicatorView: StatusIndicatorView!
    
    private func getReactionsForTable(_ tableView: UITableView) -> [Content] {
        switch tableView {
        case self.featuredTable:
            return self.featuredContent
        case self.subscriptionsTable:
            return self.subscriptionContent
        case self.recentsTable:
            return self.recentContent
        default:
            return []
        }
    }

    private func handleApplicationActiveStateChanged(active: Bool) {
        guard active else {
            if self.selectedReactionsTable == self.recentsTable {
                SettingsManager.lastFeedView = Date()
            }
            return
        }
        self.scrollRecentIfNeeded()
    }

    private func scrollRecentIfNeeded() {
        // Scroll to the top of Recent feed if it's been more than 10 mins
        guard self.isFrontPage && SettingsManager.lastFeedView.timeIntervalSinceNow < -600 else {
            return
        }
        // Do not animate or play visible videoView if table is not selected
        self.selectedReactionsTable == self.recentsTable ?
            self.scrollToTop() :
            self.recentsTable.setContentOffset(.zero, animated: false)

    }

    private func playVisibleVideoView() {
        guard
            self.view.window != nil,
            let indexPath = self.currentIndexPath,
            let cell = self.selectedReactionsTable.cellForRow(at: indexPath) as? ContentCell,
            !cell.isInTextMode,
            let view = cell.videoView
            else { return }
        if let previous = VideoView.currentlyPlayingInstance, previous != view, let duration = previous.videoDuration {
            Logging.debug("Content Playback Event", [
                "Event": "Cancel",
                "PlaybackDuration": previous.playbackDuration,
                "VideoDuration": duration,
                "PlaybackRatio": previous.playbackDuration / duration])
        }
        view.play()
        if let offset = self.contentOffset {
            view.seek(to: offset)
            self.contentOffset = nil
        }
        Logging.debug("Content Playback Start", ["Section": self.selectedSectionName])
    }

    @objc private dynamic func handleRefreshSubscriptions() {
        Logging.log("Pull Refresh Subscriptions")
        ContentService.instance.loadSubscriptionContent()
    }

    private func setupContentTable(tableView: UITableView) {
        tableView.register(UINib(nibName: "ContentCell", bundle: nil), forCellReuseIdentifier: "ContentCell")
        tableView.delegate = self
        tableView.dataSource = self
        (tableView.subviews.first as? UIScrollView)?.delaysContentTouches = false
        tableView.isPagingEnabled = false
        tableView.frame = CGRect(origin: .zero, size: CGSize(width: self.view.bounds.width, height: self.view.bounds.height + 2))
    }

    private func switchToContentList(_ contentListIndex: Int) {
        self.view.endEditing(true)
        VideoView.pauseAll()
        self.statusIndicatorView.isHidden = true

        self.selectedContentListIndex = contentListIndex
        self.segmentedControl.selectedSegmentIndex = contentListIndex
        Logging.debug("Feed Section Changed", ["Section": self.selectedSectionName])

        self.featuredTable.isHidden = true
        self.recentsTable.isHidden = true
        self.subscriptionsTable.isHidden = true
        self.selectedReactionsTable.isHidden = false
        self.tagVideosCTAView.isHidden = true

        switch contentListIndex {
        case SECTION_FOLLOWING:
            SettingsManager.lastFeedView = Date()
            self.playVisibleVideoView()
        case SECTION_FEATURED:
            SettingsManager.lastFeedView = Date()
            self.playVisibleVideoView()
        case SECTION_RECENTS:
            if ContentService.instance.hasLoadedRecents {
                let recents = ContentService.instance.recentContent
                if recents.isEmpty {
                    ContentService.instance.loadRecentContent()
                }
                self.recentContent = recents
                self.recentsTable.reloadData()
            }
            self.playVisibleVideoView()
        default:
            break
        }
    }

    private func updateFeaturedContent() {
        // TODO: Remove Featured content logic
        self.featuredContent = ContentService.instance.featuredContent
        self.featuredTable.reloadData()
        self.playVisibleVideoView()
    }

    private func updateSubscriptionContent() {
        self.statusIndicatorView.hide()
        
        self.subscriptionContent = ContentService.instance.subscriptionContent
        self.subscriptionsTable.reloadData()
        self.refreshSubsControl.endRefreshing()
        self.playVisibleVideoView()
        guard !self.didTryShowSubs else {
            return
        }
        self.didTryShowSubs = true
    }

    private func updateRecentContent() {
        guard self.selectedContentListIndex == SECTION_RECENTS else {
            return
        }
        self.recentContent = ContentService.instance.recentContent
        self.recentsTable.reloadData()
        self.playVisibleVideoView()
    }
}
