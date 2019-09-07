import GrowingTextView
import UIKit
import XLActionController

class MessagesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, GrowingTextViewDelegate {
    
    var thread: MessageThread! {
        didSet {
            self.updateMessages()
        }
    }
    
    @IBOutlet weak var inputContainer: UIView!
    @IBOutlet weak var inputTextView: GrowingTextView!
    @IBOutlet weak var keyboardHeight: NSLayoutConstraint!
    @IBOutlet weak var messagesTable: UITableView!
    @IBOutlet weak var otherImageView: UIImageView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var verifiedBadgeImage: UIImageView!
    @IBOutlet weak var moreButton: UIButton!
    @IBOutlet weak var optionsButton: UIButton!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.inputTextView.delegate = self
        self.inputTextView.maxLength = 500
        self.inputTextView.trimWhiteSpaceWhenEndEditing = false
        self.inputTextView.placeholder = "New Message"
        self.inputTextView.placeholderColor = UIColor.white.withAlphaComponent(0.4)
        self.inputTextView.tintColor = .uiYellow
        self.inputTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 66)
        self.inputTextView.minHeight = 40.0
        self.inputTextView.maxHeight = 140
        self.automaticallyAdjustsScrollViewInsets = false

        self.messagesTable.dataSource = self
        self.messagesTable.delegate = self
        self.messagesTable.register(UINib(nibName: "MessageCell", bundle: nil), forCellReuseIdentifier: "MessageCell")
        self.messagesTable.register(UINib(nibName: "PaymentCell", bundle: nil), forCellReuseIdentifier: "PaymentCell")
        self.messagesTable.register(UINib(nibName: "RequestCell", bundle: nil), forCellReuseIdentifier: "RequestCell")

        self.messagesTable.rowHeight = UITableViewAutomaticDimension
        self.messagesTable.estimatedRowHeight = 80
        self.messagesTable.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        self.messagesTable.keyboardDismissMode = .onDrag

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.titleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(MessagesViewController.handleTitleTapped)))
        self.otherImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(MessagesViewController.handleTitleTapped)))

        MessageService.instance.threadUpdated.addListener(self, method: MessagesViewController.handleThreadUpdated)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.verifiedBadgeImage.isHidden = true
        if self.thread.others.count == 1, let other = self.thread.others.first {
            self.titleLabel.text = other.username
            if other.isVerified {
                self.verifiedBadgeImage.isHidden = false
            }
            self.otherImageView.af_setImage(withURL: other.imageURL)
            self.optionsButton.isHidden = false
            self.moreButton.isHidden = false
        } else {
            self.titleLabel.text = "\(self.thread.others.count) members"
            self.otherImageView.image = #imageLiteral(resourceName: "group")
            self.moreButton.isHidden = true
            self.optionsButton.isHidden = true
        }
        self.isLoadingMessages = true
        MessageService.instance.loadMessages(for: self.thread) { cursor in
            self.isLoadingMessages = false
            self.cursor = cursor
            self.scrollToBottom(animated: false)
        }
        MessageService.instance.markSeen(thread: self.thread)
        NotificationCenter.default.addObserver(
            self, selector: #selector(MessagesViewController.keyboardEvent),
            name: .UIKeyboardWillChangeFrame, object: nil)
        self.inputTextView.becomeFirstResponder()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UITableView

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !self.isLoadingMessages, self.thread != nil, self.cursor != nil else {
            return
        }
        if scrollView.contentOffset.y < -20 {
            self.isLoadingMessages = true
            MessageService.instance.loadMessages(for: self.thread, cursor: self.cursor) { cursor in
                self.isLoadingMessages = false
                self.cursor = cursor
            }
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = self.messages[indexPath.row]
        let isCurrentUser = message.accountId == BackendClient.api.session?.id
        switch message.type {
        case .currency:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PaymentCell") as! PaymentCell
            cell.paymentLabel.text = "\(message.text)!"
            cell.commentLabel.text = "\"\(message.data["comment"] as? String ?? "😊")\""
            cell.containerStackView.alignment =
                isCurrentUser ? .trailing : .leading
            return cell
        case .request:
            let cell = tableView.dequeueReusableCell(withIdentifier: "RequestCell") as! RequestCell
            cell.titleLabel.text = message.data["title"] as? String ?? message.text
            if let url = (message.data["thumb_url"] as? String).flatMap(URL.init(string:)) {
                cell.contentImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
            } else {
                cell.contentImageView.af_cancelImageRequest()
                cell.contentImageView.image = #imageLiteral(resourceName: "relatedContent")
            }
            if isCurrentUser {
                cell.requesterUsername = BackendClient.api.session?.username
            } else {
                cell.requesterUsername = self.thread.account(id: message.accountId).username
            }
            cell.contentId = message.data["id"] as? Int64
            cell.contentURL = (message.data["url"] as? String).flatMap(URL.init(string:))
            cell.isByCurrentUser = isCurrentUser
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell") as! MessageCell
            if isCurrentUser {
                cell.userMessageLabel.text = message.text
                cell.userMessageLabel.relevantUsername = BackendClient.api.session?.username
                cell.userMessageContainer.isHidden = false
                cell.headerView.isHidden = true
            } else {
                cell.otherMessageLabel.text = message.text
                cell.otherMessageContainer.isHidden = false
                if let user = self.thread.others.first(where: { $0.id == message.accountId }) {
                    cell.otherMessageLabel.relevantUsername = user.username
                    cell.senderLabel.text = user.username
                    cell.senderImageView.af_setImage(withURL: user.imageURL)
                }
                cell.headerView.isHidden = self.thread.others.count == 1 ||
                    (indexPath.row != 0 &&
                    self.messages[indexPath.row - 1].accountId == message.accountId)
            }
            return cell
        }
    }
    
    // MARK: - UITextView

    func textViewDidChange(_ textView: UITextView) {
        self.sendButton.isHidden = textView.text?.isEmpty ?? true
    }
    
    func textViewDidChangeHeight(_ textView: GrowingTextView, height: CGFloat) {
        UIView.animate(withDuration: 0.2) {
            self.inputContainer.layoutIfNeeded()
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text == "\n" else {
            return true
        }
        Logging.log("Messages Action",  ["Result": "SendMessage"])
        self.sendMessage()
        return false
    }
    
    // MARK: - Actions
    
    @IBAction func backTapped(_ sender: Any) {
        self.navigationController?.popViewController(animated: true)
    }
    
    @IBAction func moreTapped(_ sender: Any) {
        Logging.log("Messages Action",  ["Result": "More"])
        guard thread.others.count == 1, let account = self.thread.others.first else {
            return
        }
        let sheet = ActionSheetController()
        sheet.addAction(Action("Request Reaction", style: .default) { _ in
            Logging.log("Messages More Action", ["Result": "Request"])
            self.getProfile(for: account) {
                if let profile = $0 {
                    let pickSource = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "PickSource") as! PickSourceViewController
                    pickSource.mode = .request(account: profile)
                    pickSource.modalPresentationStyle = .overCurrentContext
                    pickSource.modalTransitionStyle = .crossDissolve
                    self.present(pickSource, animated: true)
                }
            }
        })
        sheet.addAction(Action("Send Coins 😎", style: .default) { _ in
            Logging.log("Messages More Action", ["Result": "SendCoins"])
            self.getProfile(for: account) {
                if let profile = $0 {
                    TabBarController.showRewards(for: profile)
                }
            }
        })
        sheet.addCancel() {
            Logging.log("Messages More Action", ["Result": "Cancel"])
        }
        self.present(sheet, animated: true)
    }

    @IBAction func optionsTapped(_ sender: Any) {
        // TODO YOLO logging, options
        guard self.thread.others.count == 1, let other = self.thread.others.first else {
            return
        }
        self.inputTextView.resignFirstResponder()
        Logging.debug("Messages Action", ["Action": "Options"])
        let sheet = ActionSheetController(title: nil)
        sheet.addAction(Action("Block & Report", style: .destructive) { _ in
            Logging.log("Messages Options", ["Action": "Block User"])
            self.presentBlockAlert(for: other.id, username: other.username)
        })
        sheet.addCancel()
        sheet.configurePopover(sourceView: self.moreButton)
        self.present(sheet, animated: true)
    }

    @IBAction func sendTapped(_ sender: Any) {
        Logging.log("Messages Action",  ["Result": "SendButton"])
        self.sendMessage()
    }

    // MARK: - Private

    private var cursor: String? = nil
    private var isLoadingMessages = false
    private var isFirstTimeAppearing = true
    private var messages = [Message]()
    private var statusIndicatorView: StatusIndicatorView!

    private func getProfile(for account: ThreadAccount, callback: @escaping (Profile?) -> ()) {
        Logging.log("Messages Action",  ["Result": "Profile"])
        self.statusIndicatorView.showLoading()
        Intent.getProfile(identifier: String(account.id)).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            guard $0.successful, let data = $0.data else {
                callback(nil)
                return
            }
            callback(Profile(data: data))
        }
    }

    private func handleThreadUpdated(thread: MessageThread) {
        guard thread.id == self.thread?.id else {
            return
        }
        MessageService.instance.markSeen(thread: thread)
        DispatchQueue.main.async {
            self.thread = thread
        }
    }
    
    @objc private dynamic func handleTitleTapped() {
        let others = self.thread.others
        guard others.count == 1, let other = others.first else {
            let sheet = ActionSheetController(title: "\(others.count) members")
            sheet.configurePopover(sourceView: self.titleLabel)
            others.forEach { user in
                sheet.addAction(Action("@\(user.username)", style: .default) { _ in
                    self.selectUser(identifier: String(user.id))
                })
            }
            sheet.addCancel()
            self.present(sheet, animated: true)
            return
        }
        self.selectUser(identifier: String(other.id))
    }

    private func presentBlockAlert(for accountId: Int64, username: String, callback: ((Bool) -> ())? = nil) {
        let alert = UIAlertController(
            title: "Are you sure?",
            message: "Continuing will block @\(username) and they will not be able to reach you.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Block @\(username)", style: .destructive) { _ in
            Logging.danger("Block User", ["Action": "Block", "AccountId": accountId])
            self.statusIndicatorView.showLoading()
            Intent.blockUser(identifier: String(accountId)).perform(BackendClient.api) {
                guard $0.successful else {
                    self.statusIndicatorView.hide()
                    let alert = UIAlertController(
                        title: "Oops!",
                        message: "Something went wrong. Please try again.",
                        preferredStyle: .alert)
                    alert.addCancel(title: "OK") {
                        callback?(false)
                    }
                    self.present(alert, animated: true)
                    return
                }
                // Reload data to account for newly blocked user.
                ContentService.instance.loadFeaturedContent()
                ContentService.instance.loadRecentContent()
                self.statusIndicatorView.showConfirmation(title: "Blocked")
                self.thread.hide()
                self.navigationController?.popViewController(animated: true)
                callback?(true)
            }
        })
        alert.addCancel() {
            Logging.log("Block User", ["Action": "Cancel"])
            callback?(false)
        }
        self.present(alert, animated: true)
    }
    
    private func selectUser(identifier: String) {
        self.statusIndicatorView.showLoading()
        Intent.getProfile(identifier: identifier).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            guard $0.successful, let data = $0.data else {
                return
            }
            TabBarController.select(account: Profile(data: data))
        }
    }
    
    private func scrollToBottom(animated: Bool = true) {
        let messageCount = self.thread.messages.count
        guard messageCount > 0 else {
            return
        }
        let indexPath = IndexPath(row: messageCount - 1, section: 0)
        self.messagesTable.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    private func sendMessage() {
        let text = self.inputTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        do {
            try self.thread.message(type: .text, text: text)
            self.updateMessages()
        } catch {
            // TODO: Error handling
        }
        self.inputTextView.text = ""
        self.sendButton.isHidden = true
    }

    @objc private dynamic func keyboardEvent(notification: NSNotification) {
        guard
            let keyboardHeight = self.keyboardHeight,
            let windowHeight = UIApplication.shared.keyWindow?.bounds.height,
            let view = self.view
            else { return }
        let safeY: CGFloat
        if #available(iOS 11.0, *) {
            safeY = self.view.safeAreaInsets.bottom
        } else {
            safeY = 0
        }
        let info = notification.userInfo!
        let frame = info[UIKeyboardFrameEndUserInfoKey] as! CGRect
        let targetY = min(frame.minY - windowHeight + safeY, 0)
        if self.isFirstTimeAppearing {
            self.isFirstTimeAppearing = false
            UIView.performWithoutAnimation {
                keyboardHeight.constant = targetY
                view.layoutIfNeeded()
            }
            self.scrollToBottom(animated: false)
        } else {
            view.layoutIfNeeded()
            let duration = (info[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue
            UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut, animations: {
                keyboardHeight.constant = targetY
                view.layoutIfNeeded()
            }) { _ in
                if keyboardHeight.constant < 0 {
                    self.scrollToBottom()
                }
            }
        }
    }
    
    private func updateMessages() {
        let latestMessages: [Message] = self.thread.messages.values.reversed()

        let wasEmpty = self.messages.isEmpty
        let hasNewMessage = self.messages.last?.id != latestMessages.last?.id
        let addedCount = latestMessages.count - self.messages.count
        let offset = self.messagesTable.contentOffset.y

        // Refresh data
        self.messages = latestMessages
        self.messagesTable.reloadData()
        self.view.layoutIfNeeded()

        // If there are new messages, scroll to bottom
        // Otherwise, preserve current scroll offset
        if hasNewMessage {
            self.scrollToBottom(animated: !wasEmpty)
        } else if addedCount > 0 {
            self.messagesTable.scrollToRow(at: IndexPath(row: addedCount, section: 0), at: .top, animated: false)
            let point = CGPoint(x: 0, y: self.messagesTable.contentOffset.y + offset)
            self.messagesTable.setContentOffset(point, animated: false)
        }
    }
}

class MessageCell: UITableViewCell {
    @IBOutlet weak var userMessageContainer: UIView!
    @IBOutlet weak var userMessageLabel: TagLabel!
    @IBOutlet weak var otherMessageContainer: UIView!
    @IBOutlet weak var otherMessageLabel: TagLabel!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var senderLabel: UILabel!
    @IBOutlet weak var senderImageView: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.userMessageLabel.enabledTypes.append(.url)
        self.otherMessageLabel.enabledTypes.append(.url)
        self.headerView.isHidden = true
    }
    
    override func prepareForReuse() {
        self.userMessageContainer.isHidden = true
        self.userMessageLabel.text = nil
        self.otherMessageContainer.isHidden = true
        self.otherMessageLabel.text = nil
        self.senderLabel.text = "Not available"
        self.senderImageView.af_cancelImageRequest()
        self.senderImageView.image = #imageLiteral(resourceName: "single")
        self.headerView.isHidden = true
    }
}

class PaymentCell: UITableViewCell {
    @IBOutlet weak var paymentLabel: UILabel!
    @IBOutlet weak var containerStackView: UIStackView!
    @IBOutlet weak var commentLabel: UILabel!
}

class RequestCell: UITableViewCell {
    @IBOutlet weak var containerStackView: UIStackView!
    @IBOutlet weak var contentImageView: UIImageView!
    @IBOutlet weak var reactButton: HighlightButton!
    @IBOutlet weak var titleContainerView: UIView!
    @IBOutlet weak var titleLabel: UILabel!

    var contentId: Int64?
    var contentURL: URL?
    var requesterUsername: String?

    var isByCurrentUser: Bool = true {
        didSet {
            if self.isByCurrentUser {
                self.containerStackView.alignment = .trailing
                self.titleContainerView.backgroundColor = "4C90F5".hexColor
            } else {
                self.containerStackView.alignment = .leading
                self.titleContainerView.backgroundColor = "545454".hexColor
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.reactButton.setHeavyShadow()
    }

    @IBAction func reactTapped(_ sender: Any) {
        let ref = self.contentId.flatMap { ContentRef.id($0) }
        TabBarController.showCreate(url: self.contentURL, ref: ref, relevantUsername: self.requesterUsername,
                                    source: "Messages Request Cell React Action")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Reset data.
        self.contentId = nil
        self.contentURL = nil
        self.requesterUsername = nil
        // Reset UI components.
        self.contentImageView.af_cancelImageRequest()
        self.contentImageView.image = #imageLiteral(resourceName: "relatedContent")
        self.titleLabel.text = nil
    }
}
