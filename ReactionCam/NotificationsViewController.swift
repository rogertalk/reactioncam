
import UIKit
import UserNotifications

fileprivate let HEADER_HEIGHT = 120.0

class NotificationsViewController: UIViewController,
    ConversationImportDelegate,
    NotificationCellDelegate,
    UITableViewDelegate,
    UITableViewDataSource
{
    @IBOutlet weak var addButton: UIButton!
    @IBOutlet weak var emptyView: UIView!
    @IBOutlet weak var enableNotificationsButton: UIButton!
    @IBOutlet weak var threadsTable: UITableView!
    @IBOutlet weak var notifsTable: UITableView!
    @IBOutlet weak var rateButton: UIButton!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var shareFriendsButton: UIButton!

    var notifs: [AccountNotification] = [] {
        didSet {
            self.emptyView.isHidden = !self.notifs.isEmpty
            self.statusIndicatorView.hide()
            if oldValue.count != self.notifs.count || zip(oldValue, self.notifs).contains(where: { $0.id != $1.id || $0.groupCount != $1.groupCount }) {
                self.notifsTable.reloadData()
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // MARK: - UIViewController

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppDelegate.applicationActiveStateChanged.removeListener(self)
        NotificationService.instance.notifsChanged.removeListener(self)
        for cell in self.notifsTable.visibleCells {
            (cell as? NotificationCell)?.cellDidEndDisplaying()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.resetPullToRefresh()
        if !self.shareFriendsButton.isHidden {
            self.shareFriendsButton.pulse()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.notifsTable.register(UINib(nibName: "RequestNotificationCell", bundle: nil), forCellReuseIdentifier: "RequestNotificationCell")
        self.notifsTable.delegate = self
        self.notifsTable.dataSource = self
        self.notifsTable.contentInset = UIEdgeInsets(top: CGFloat(HEADER_HEIGHT), left: 0, bottom: 0, right: 0)
        (self.notifsTable.subviews.first as? UIScrollView)?.delaysContentTouches = false
        self.refreshNotifsControl.tintColor = .white
        self.refreshNotifsControl.addTarget(self, action: #selector(NotificationsViewController.refreshNotifsPulled), for: .valueChanged)
        self.notifsTable.refreshControl = self.refreshNotifsControl

        self.threadsTable.delegate = self
        self.threadsTable.dataSource = self
        self.threadsTable.contentInset = UIEdgeInsets(top: CGFloat(HEADER_HEIGHT), left: 0, bottom: 0, right: 0)
        self.refreshThreadsControl.tintColor = .white
        self.refreshThreadsControl.addTarget(self, action: #selector(NotificationsViewController.refreshThreadsPulled), for: .valueChanged)
        self.threadsTable.refreshControl = self.refreshThreadsControl

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        if Recorder.instance.composer != nil && SettingsManager.shouldShowNewBadge(for: "plus_button") {
            TabBarController.instance?.tooltip.show()
        }

        let unseen = NotificationService.instance.unseenCount
        self.segmentedControl.setTitle("FEED\(unseen > 0 ? " (\(unseen))" : "")", forSegmentAt: 0)

        MessageService.instance.threadsChanged.addListener(self, method: NotificationsViewController.handleThreadsChanged)
        MessageService.instance.threadUpdated.addListener(self, method: NotificationsViewController.handleThreadUpdated)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updateEnableNotificationsButton()
        self.rateButton.isHidden = !SettingsManager.shouldAskToRate
        self.shareFriendsButton.isHidden = !SettingsManager.shouldAskToShare
        self.notifs = NotificationService.instance.notifs

        // Show loading if we have no activity and it's still loading.
        let isLoading = NotificationService.instance.loadNotifications()
        if self.notifs.isEmpty && isLoading {
            self.statusIndicatorView.showLoading()
        }

        if !self.notifsTable.isHidden {
            for cell in self.notifsTable.visibleCells {
                (cell as? NotificationCell)?.cellWillDisplay()
            }
        }

        AppDelegate.applicationActiveStateChanged.addListener(self, method: NotificationsViewController.handleApplicationActiveStateChanged)
        NotificationService.instance.notifsChanged.addListener(self, method: NotificationsViewController.handleNotifsUpdated)

        self.updateThreads()
    }

    func scrollToTop() {
        let table = self.segmentedControl.selectedSegmentIndex == 0 ? self.notifsTable : self.threadsTable
        table?.setContentOffset(CGPoint(x: 0.0, y: -HEADER_HEIGHT), animated: true)
    }

    // MARK: - NotificationCellDelegate

    func notificationCell(_ cell: NotificationCell, receivedTapOn target: NotificationCell.TapTarget) {
        self.handleNotifTapped(cell, target: target)
    }

    // MARK: - UITableViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let contentHeight = scrollView.contentSize.height
        let refreshHeight = scrollView.bounds.height * 1.5
        if contentHeight > refreshHeight, scrollView.contentOffset.y > (scrollView.contentSize.height - refreshHeight) {
            MessageService.instance.loadThreads(page: true)
        }
    }
    
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch tableView {
        case self.threadsTable:
            return true
        default:
            return indexPath.section != 0
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? NotificationCell)?.cellDidEndDisplaying()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch tableView {
        case self.threadsTable:
            guard let messages = Bundle.main.loadNibNamed("MessagesViewController", owner: nil, options: nil)?.first as? MessagesViewController else {
                return
            }
            messages.thread =
                MessageService.instance.threads.values[indexPath.row]
            self.navigationController?.pushViewController(messages, animated: true)
            return
        default:
            guard let cell = tableView.cellForRow(at: indexPath) as? NotificationCell else {
                return
            }
            self.handleNotifTapped(cell, target: .body)
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let segment = self.segmentedControl.selectedSegmentIndex
        guard tableView == self.notifsTable && segment == 0 || tableView == self.threadsTable && segment == 1 else {
            return
        }
        (cell as? NotificationCell)?.cellWillDisplay()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch tableView {
        case self.threadsTable:
            return 90
        default:
            if indexPath.section == 0 {
                return 90
            } else {
                let notif = self.notifs[indexPath.row]
                return notif.type == "content-request" ? 290 : 80
            }
        }
    }
    
    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch tableView {
        case self.threadsTable:
            return MessageService.instance.threads.count
        default:
            return section == 0 ? 1 : self.notifs.count
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        switch tableView {
        case self.threadsTable:
            return 1
        default:
            return 2
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch tableView {
        case self.threadsTable:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MessageThreadCell") as! MessageThreadCell
            let thread = MessageService.instance.threads.values[indexPath.row]
            cell.threadNameLabel.text = thread.title
            if thread.others.count == 1, let other = thread.others.first, other.isVerified {
                cell.verifiedBadgeImageView.isHidden = false
            }
            cell.timestampLabel.text = thread.lastInteraction.timeLabelShort
            if let lastMessage = thread.messages.first?.value {
                cell.lastMessageLabel.text = lastMessage.accountId == BackendClient.api.session!.id ? "You: \(lastMessage.text)" : lastMessage.text
            } else {
                cell.lastMessageLabel.text = "..."
            }
            if !thread.seen {
                cell.lastMessageLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
                cell.lastMessageLabel.textColor = .white
                cell.arrowLabel.textColor = .uiYellow
                cell.timestampLabel.textColor = .uiYellow
                cell.threadNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            }
            if thread.others.count == 1, let url = thread.imageURL {
                cell.avatarImageView.af_setImage(withURL: url)
            } else {
                cell.avatarImageView.image = #imageLiteral(resourceName: "group")
            }
            return cell
        default:
            switch indexPath.section {
            case 0:
                return tableView.dequeueReusableCell(withIdentifier: "FindFriendsCell", for: indexPath)
            default:
                let notif = self.notifs[indexPath.row]
                let cell: NotificationCell
                if notif.type == "content-request" {
                    cell = tableView.dequeueReusableCell(withIdentifier: "RequestNotificationCell", for: indexPath) as! RequestNotificationCell
                } else {
                    cell = tableView.dequeueReusableCell(withIdentifier: "NotificationCell", for: indexPath) as! GeneralNotificationCell
                }
                cell.delegate = self
                cell.notif = notif
                return cell
            }
        }
    }

    // MARK: - ConversationImportDelegate

    var conversationImportAnchorView: UIView {
        return self.addButton
    }

    // MARK: - Actions

    @IBAction func addTapped(_ sender: Any) {
        Logging.log("Notifications Action", ["Action": "Add Button", "Empty": self.notifs.isEmpty])
        let alert = ConversationImportAlert(title: "Start a REACTION CHALLENGE!", message: nil, source: "Notifications", importActions: [.invite], owner: self, delegate: self)
        alert.show()
        self.importAlert = alert
    }

    @IBAction func enableNotificationsTapped(_ sender: UIButton) {
        Logging.log("Notifications Action", ["Action": "Enable Notifications", "Empty": self.notifs.isEmpty])
        AppDelegate.requestNotificationPermissions(presentAlertWith: self, source: "NotificationsView") { success in
            self.enableNotificationsButton.isHidden = success
        }
    }

    @IBAction func rateTapped(_ sender: Any) {
        Logging.log("Notifications Action", ["Action": "Rate", "Empty": self.notifs.isEmpty])
        TabBarController.instance?.showRate(source: "Notifications")
        self.rateButton.hideAnimated()
    }

    @IBAction func findFriendsTapped(_ sender: Any) {
        guard let vc = Bundle.main.loadNibNamed("SuggestedUsersViewController", owner: nil, options: nil)?.first as? SuggestedUsersViewController else {
            return
        }
        self.navigationController!.pushViewController(vc, animated: true)
        Logging.log("Notifications Action", ["Action": "FindFriends", "Empty": self.notifs.isEmpty])
    }

    @IBAction func segmentValueChanged(_ sender: Any) {
        let showNotifs = self.segmentedControl.selectedSegmentIndex == 0
        self.notifsTable.isHidden = !showNotifs
        self.threadsTable.isHidden = showNotifs
        for cell in self.notifsTable.visibleCells {
            guard let cell = cell as? NotificationCell else {
                continue
            }
            if showNotifs {
                cell.cellWillDisplay()
            } else {
                cell.cellDidEndDisplaying()
            }
        }
    }

    @IBAction func sharefriendsTapped(_ sender: Any) {
        self.shareFriendsButton.isHidden = true
        TabBarController.instance?.showAskShare()
    }

    // MARK: - Private

    private let refreshNotifsControl = UIRefreshControl()
    private let refreshThreadsControl = UIRefreshControl()

    private var statusIndicatorView: StatusIndicatorView!
    private var importAlert: ConversationImportAlert?

    private func handleApplicationActiveStateChanged(active: Bool) {
        if active {
            self.updateEnableNotificationsButton()
        }
        for cell in self.notifsTable.visibleCells {
            guard let cell = cell as? NotificationCell else { continue }
            if active {
                cell.cellWillDisplay()
            } else {
                cell.cellDidEndDisplaying()
            }
        }
        self.resetPullToRefresh()
    }

    private func handleNotifsUpdated() {
        self.notifs = NotificationService.instance.notifs
        let unseen = NotificationService.instance.unseenCount
        self.segmentedControl.setTitle("FEED\(unseen > 0 ? " (\(unseen))" : "")", forSegmentAt: 0)
    }

    private func handleNotifTapped(_ cell: NotificationCell, target: NotificationCell.TapTarget) {
        guard let notif = cell.notif else {
            return
        }
        // Mark the notification as seen immediately.
        cell.markAsSeen()
        // Log the tap.
        let area: String
        switch target {
        case .action:
            area = "ActionButton"
        case .avatar:
            area = "AvatarImage"
        case .body:
            area = "Body"
        case .content:
            area = "ContentImage"
        }
        Logging.log("Notification Tapped", ["Area": area, "Type": notif.type])
        // Handle the tap.
        let props = notif.properties
        // First, handle taps on the avatar.
        var accountId: Int64?
        switch target {
        case .avatar:
            switch notif.type {
            case "content-comment":
                accountId = props["commenter_id"] as? Int64
            case "content-created", "content-mention", "content-referenced", "content-request-fulfilled":
                accountId = props["creator_id"] as? Int64
            case "content-featured", "streak":
                TabBarController.select(tab: .profile, source: "NotificationsView")
                return
            case "content-request":
                accountId = props["requester_id"] as? Int64
            case "content-vote":
                accountId = props["voter_id"] as? Int64
            case "custom":
                if let url = (props["avatar_open_url"] as? String).flatMap(URL.init(string:)) {
                    UIApplication.shared.open(url)
                    return
                }
            default:
                break
            }
        case .content where notif.type == "custom":
            if let url = (props["content_open_url"] as? String).flatMap(URL.init(string:)) {
                UIApplication.shared.open(url)
                return
            }
        default:
            break
        }
        if let id = accountId {
            Intent.getProfile(identifier: String(id)).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    return
                }
                TabBarController.select(account: Profile(data: data))
            }
            return
        }
        // Then treat all other taps as an action tap.
        switch notif.type {
        case "account-follow":
            guard let accountId = props["follower_id"] as? Int64 else {
                break
            }

            guard target != .action else {
                FollowService.instance.follow(ids: [accountId])
                cell.hideCTA()
                let alert = UIAlertController(title: "Subscribed back!", message: nil, preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }

            self.requestNotifs {
                guard notif.groupCount == 1 else {
                    let vc = self.storyboard!.instantiateViewController(withIdentifier: "AccountList") as! AccountListViewController
                    vc.type = .followers(account: BackendClient.api.session!)
                    self.navigationController!.pushViewController(vc, animated: true)
                    return
                }
                Intent.getProfile(identifier: String(accountId)).perform(BackendClient.api) {
                    guard $0.successful, let data = $0.data else {
                        return
                    }
                    TabBarController.select(account: Profile(data: data))
                }
            }
        case "chat-join", "chat-mention", "chat-message", "chat-owner-join":
            guard let channelId = props["channel_id"] as? String else {
                break
            }
            Intent.getProfile(identifier: channelId).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    return
                }
                TabBarController.select(account: Profile(data: data), showChat: true)
            }
        case "coins-received":
            guard let accountId = props["payer_id"] as? Int64 else {
                break
            }
            Intent.getProfile(identifier: String(accountId)).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    return
                }
                TabBarController.select(account: Profile(data: data))
            }
        case "content-comment":
            guard let contentId = props["content_id"] as? Int64, let offset = props["comment_offset"] as? Int else {
                break
            }
            if offset == -1 {
                self.statusIndicatorView.showLoading()
                Intent.getContent(id: contentId).perform(BackendClient.api) {
                    self.statusIndicatorView.hide()
                    guard $0.successful, let content = $0.data.flatMap(Content.init(data:)) else {
                        return
                    }
                    TabBarController.select(originalContent: content,
                                            inject: nil,
                                            tab: .comments,
                                            animated: true,
                                            source: "Comment App Notif")
                }
            } else {
                TabBarController.select(contentId: contentId,
                                        offset: max(Double(offset - 500) / 1000, 0))
            }
        case "content-created":
            guard let contentId = props["content_id"] as? Int64 else {
                break
            }
            if target == .action, let username = props["creator_username"] as? String {
                if let contentURL = (props["content_url"] as? String).flatMap(URL.init(string:)) {
                    TabBarController.showCreate(url: contentURL, ref: .id(contentId), relevantUsername: username,
                                                source: "Notif (Content Created) Action")
                    cell.hideCTA()
                    break
                }
                self.statusIndicatorView.showLoading()
                Intent.getContent(id: contentId).perform(BackendClient.api) {
                    self.statusIndicatorView.hide()
                    guard $0.successful, let content = $0.data.flatMap(Content.init(data:)) else {
                        return
                    }
                    TabBarController.showCreate(url: content.originalURL ?? content.videoURL, ref: .id(contentId),
                                                relevantUsername: username, source: "Notif (Content Created) Action")
                    cell.hideCTA()
                }
                break
            }
            TabBarController.select(contentId: contentId, offset: nil)
        case "content-mention", "content-vote":
            guard let contentId = props["content_id"] as? Int64 else {
                break
            }
            TabBarController.select(contentId: contentId, offset: nil)
        case "content-featured":
            guard let contentId = props["content_id"] as? Int64 else {
                break
            }
            self.requestNotifs {
                TabBarController.select(contentId: contentId)
            }
        case "content-referenced", "content-request-fulfilled":
            guard let contentId = props["content_id"] as? Int64 else {
                break
            }
            if target == .action {
                TabBarController.select(contentId: contentId, action: .repost)
                cell.hideCTA()
                break
            }
            self.requestNotifs {
                TabBarController.select(contentId: contentId)
            }
        case "content-request":
            guard
                let urlString = props["content_url"] as? String,
                let url = URL(string: urlString)
                else { break }
            let ref = (props["content_id"] as? Int64).flatMap { ContentRef.id($0) }
            let username = props["requester_username"] as! String
            self.requestNotifs {
                TabBarController.showCreate(url: url, ref: ref, relevantUsername: username,
                                            source: "Notif (Reaction Request) Action")
            }
        case "custom":
            if let url = (props["action_open_url"] as? String).flatMap(URL.init(string:)) {
                UIApplication.shared.open(url)
            }
        case "friend-joined":
            guard let accountId = props["friend_id"] as? Int64 else {
                break
            }
            if target == .action {
                FollowService.instance.follow(ids: [accountId])
                cell.hideCTA()
                break
            }
            Intent.getProfile(identifier: String(accountId)).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    return
                }
                TabBarController.select(account: Profile(data: data))
            }
        case "streak":
            let days = props["days"] as! Int
            let copy = SettingsManager.shareStreakCopy(days: days)
            let vc = UIActivityViewController(activityItems: [DynamicActivityItem(copy)], applicationActivities: nil)
            vc.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
            vc.configurePopover(sourceView: cell)
            self.present(vc, animated: true)
        case "update-app":
            let link = "https://itunes.apple.com/us/app/reaction-cam/id1225620956?ls=1&mt=8"
            guard let url = URL(string: link), UIApplication.shared.canOpenURL(url) else {
                break
            }
            UIApplication.shared.open(url)
        default:
            break
        }
    }

    private func handleThreadsChanged(newThreads: [MessageThread], diff: MessageService.ThreadsDiff) {
        self.updateThreads()
    }

    private func handleThreadUpdated(thread: MessageThread) {
        self.updateThreads()
    }

    @objc private dynamic func refreshNotifsPulled(_ sender: UIRefreshControl) {
        NotificationService.instance.loadNotificationsForced { _ in
            sender.endRefreshing()
        }
    }

    @objc private dynamic func refreshThreadsPulled(_ sender: UIRefreshControl) {
        MessageService.instance.loadThreads { _ in
            sender.endRefreshing()
        }
    }

    private func requestNotifs(then callback: @escaping () -> ()) {
        guard !self.enableNotificationsButton.isHidden else {
            callback()
            return
        }
        AppDelegate.requestNotificationPermissions(presentAlertWith: self, source: "NotificationsView", type: .reminder) {
            self.enableNotificationsButton.isHidden = $0
            callback()
        }
    }

    private func resetPullToRefresh() {
        self.refreshNotifsControl.endRefreshing()
        self.refreshThreadsControl.endRefreshing()
    }
    
    private func updateEnableNotificationsButton() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.enableNotificationsButton.isHidden = settings.authorizationStatus == .authorized
            }
        }
    }

    private func updateThreads() {
        let unseen = MessageService.instance.unseenCount
        self.segmentedControl.setTitle("\(unseen > 0 ? "🔴 " : "")MESSAGES\(unseen > 0 ? " (\(unseen))" : "")", forSegmentAt: 1)
        self.threadsTable.reloadData()
    }
}

class MessageThreadCell: SeparatorCell {
    @IBOutlet weak var arrowLabel: UILabel!
    @IBOutlet weak var lastMessageLabel: UILabel!
    @IBOutlet weak var threadNameLabel: UILabel!
    @IBOutlet weak var avatarImageView: UIImageView!
    @IBOutlet weak var timestampLabel: UILabel!
    @IBOutlet weak var verifiedBadgeImageView: UIImageView!

    override func prepareForReuse() {
        self.lastMessageLabel.text = nil
        self.threadNameLabel.text = nil
        self.timestampLabel.text = nil
        self.verifiedBadgeImageView.isHidden = true

        self.lastMessageLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        self.arrowLabel.textColor = .lightText
        self.lastMessageLabel.textColor = .lightText
        self.timestampLabel.textColor = .lightText

        self.threadNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)

        self.avatarImageView.image = #imageLiteral(resourceName: "single")
        self.avatarImageView.af_cancelImageRequest()
    }
}
