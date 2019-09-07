import UIKit

protocol NotificationCellDelegate: class {
    func notificationCell(_ cell: NotificationCell, receivedTapOn target: NotificationCell.TapTarget)
}

class NotificationCell: SeparatorCell {
    enum TapTarget {
        case action, avatar, body, content
    }
    
    weak var delegate: NotificationCellDelegate?
    
    var notif: AccountNotification! {
        didSet {
            guard oldValue?.id != self.notif.id || oldValue?.groupCount != self.notif.groupCount else {
                return
            }
            self.instanceId = NotificationCell.nextInstanceId
            NotificationCell.nextInstanceId += 1
            self.timer = nil
            self.refresh()
        }
    }
    
    deinit {
        self.timer = nil
    }
    
    func cellDidEndDisplaying() {
        self.timer = nil
    }
    
    func cellWillDisplay() {
        guard self.notif.shouldAutoMarkAsSeen else {
            return
        }
        self.timer = .scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
            self.markAsSeen()
        }
    }
    
    func markAsSeen() {
        NotificationService.instance.markSeen(notif: self.notif)
        UIView.animate(withDuration: 0.5) {
            self.backgroundView?.backgroundColor = .black
        }
    }
    
    func refresh() { }
    
    func hideCTA() { }
    
    // MARK: - UITableViewCell
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.timer = nil
    }
    
    // MARK: - UIView
    
    override func awakeFromNib() {
        super.awakeFromNib()
        let backgroundView = UIView()
        backgroundView.backgroundColor = .black
        self.backgroundView = backgroundView
        let highlightView = UIView()
        highlightView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        self.selectedBackgroundView = highlightView
    }
    
    // MARK: - Private
    
    fileprivate static var nextInstanceId = 0
    fileprivate var instanceId = -1
    
    private var timer: Timer? {
        didSet {
            oldValue?.invalidate()
        }
    }
}

class GeneralNotificationCell: NotificationCell {
    
    @IBOutlet weak var actionButton: HighlightButton!
    @IBOutlet weak var avatarButton: UIButton!
    @IBOutlet weak var contentButton: UIButton!
    @IBOutlet weak var mainLabel: UILabel!
    @IBOutlet weak var secondaryLabel: UILabel!
    @IBOutlet weak var verifiedBadgeImageView: UIImageView!
    
    override func refresh() {
        guard let notif = self.notif else {
            return
        }
        self.backgroundView?.backgroundColor = notif.seen ? .black : UIColor.uiBlue.withAlphaComponent(0.6)
        // Reset all visibility values.
        self.actionButton.isHidden = true
        self.avatarButton.isHidden = true
        self.contentButton.isHidden = true
        self.mainLabel.text = ""
        self.secondaryLabel.text = ""
        self.verifiedBadgeImageView.isHidden = true
        // Configure notification depending on its type.
        let props = notif.properties
        switch notif.type {
        case "account-follow":
            self.showAvatarButton(with: "follower_image_url")
            switch notif.groupCount {
            case 1:
                self.mainLabel.text = "@\(props["follower_username"] as! String)"
                let instanceId = self.instanceId
                Intent.getProfile(identifier: String(props["follower_id"] as! Int64)).perform(BackendClient.api) {
                    guard $0.successful, let data = $0.data, self.instanceId == instanceId else {
                        return
                    }
                    let account = Profile(data: data)
                    guard !account.isFollowing else {
                        return
                    }
                    self.actionButton.setTitle("✚ SUB", for: .normal)
                    self.actionButton.isHidden = false
                }
            case 2:
                self.mainLabel.text = "@\(props["follower_username"] as! String) and 1 other"
            default:
                self.mainLabel.text = "@\(props["follower_username"] as! String) and \(notif.groupCount - 1) others"
            }
            self.secondaryLabel.text = "subscribed to you"
            if notif.groupCount == 1 && (props["follower_verified"] as? Bool) == true {
                // Only show the badge when the notif is not grouped so it appears after username.
                self.verifiedBadgeImageView.isHidden = false
            }
        case "chat-join":
            self.showAvatarButton(with: "joiner_image_url")
            self.mainLabel.text = "Your LIVECHAT 🔴 is active!"
            self.secondaryLabel.text = "@\(props["joiner_username"] as! String): \(props["text"] as! String)"
            self.verifiedBadgeImageView.isHidden = (props["joiner_verified"] as? Bool) != true
        case "chat-mention", "chat-message":
            self.showAvatarButton(with: "owner_image_url")
            self.mainLabel.text = "@\(props["owner_username"] as! String)’s LIVECHAT 🔴"
            self.secondaryLabel.text = "@\(props["sender_username"] as! String): \(props["text"] as! String)"
            self.verifiedBadgeImageView.isHidden = (props["owner_verified"] as? Bool) != true
        case "chat-owner-join":
            self.showAvatarButton(with: "owner_image_url")
            self.mainLabel.text = "@\(props["owner_username"] as! String) is on LIVECHAT 🔴"
            self.secondaryLabel.text = "@\(props["owner_username"] as! String): \(props["text"] as! String)"
            self.verifiedBadgeImageView.isHidden = (props["owner_verified"] as? Bool) != true
        case "coins-received":
            self.showAvatarButton(with: "payer_image_url")
            let amount = props["amount"] as! Int
            self.mainLabel.text = (amount == 1 ? "1 COIN" : "\(amount) COINS")
            self.secondaryLabel.text = "from @\(props["payer_username"] as! String)"
        case "content-comment":
            self.showContentButton(with: "content_thumb_url")
            self.mainLabel.text = "@\(props["commenter_username"] as! String)"
            let offset = props["comment_offset"] as! Int
            if offset >= 0 {
                let min = offset / 60000, sec = offset % 60000 / 1000
                self.secondaryLabel.text = "(\(min):\(String(format: "%02d", sec))) “\(props["comment_text"] as! String)”"
            } else {
                self.secondaryLabel.text = "“\(props["comment_text"] as! String)”"
            }
            self.verifiedBadgeImageView.isHidden = (props["commenter_verified"] as? Bool) != true
        case "content-created":
            self.showContentButton(with: "content_thumb_url")
            if Recorder.instance.composer != nil {
                self.actionButton.setTitle("REACT", for: .normal)
                self.actionButton.isHidden = false
            }
            self.mainLabel.text = "@\(props["creator_username"] as! String)"
            self.secondaryLabel.text = (props["content_title"] as? String) ?? "posted a new video"
            self.verifiedBadgeImageView.isHidden = (props["creator_verified"] as? Bool) != true
        case "content-featured":
            self.showContentButton(with: "content_thumb_url")
            self.mainLabel.text = "FEATURED 🏆"
            self.secondaryLabel.text = "Your video got featured!"
        case "content-mention":
            if !self.showContentButton(with: "content_thumb_url") {
                self.showAvatarButton(with: "creator_image_url")
            }
            self.mainLabel.text = "@\(props["creator_username"] as! String)"
            self.secondaryLabel.text = "mentioned you!"
            self.verifiedBadgeImageView.isHidden = (props["creator_verified"] as? Bool) != true
        case "content-referenced":
            self.showContentButton(with: "content_thumb_url")
            self.actionButton.setTitle("REPOST", for: .normal)
            self.actionButton.isHidden = false
            self.mainLabel.text = "@\(props["creator_username"] as! String)"
            self.secondaryLabel.text = "reacted to your video!"
            self.verifiedBadgeImageView.isHidden = (props["creator_verified"] as? Bool) != true
        case "content-request-fulfilled":
            self.showContentButton(with: "content_thumb_url")
            self.actionButton.setTitle("REPOST", for: .normal)
            self.actionButton.isHidden = false
            self.mainLabel.text = "@\(props["creator_username"] as! String)"
            self.secondaryLabel.text = "reacted to your request!"
            self.verifiedBadgeImageView.isHidden = (props["creator_verified"] as? Bool) != true
        case "content-vote":
            self.showContentButton(with: "content_thumb_url")
            switch notif.groupCount {
            case 1:
                self.mainLabel.text = "@\(props["voter_username"] as! String)"
            case 2:
                self.mainLabel.text = "@\(props["voter_username"] as! String) and 1 other"
            default:
                self.mainLabel.text = "@\(props["voter_username"] as! String) and \(notif.groupCount - 1) others"
            }
            self.secondaryLabel.text = "liked your video"
            self.verifiedBadgeImageView.isHidden = (props["voter_verified"] as? Bool) != true
        case "custom":
            // Custom notification type. Properties:
            // • auto_mark_seen
            // • title, text
            // • action_label, action_open_url
            // • avatar_image_url, avatar_open_url (optional, defaults to action_open_url)
            // • content_image_url, content_open_url (optional, defaults to action_open_url)
            self.mainLabel.text = props["title"] as? String
            self.secondaryLabel.text = props["text"] as? String
            self.showAvatarButton(with: "avatar_image_url", fallbackToDefault: false)
            self.showContentButton(with: "content_image_url", fallbackToDefault: false)
            if let label = props["action_label"] as? String {
                self.actionButton.setTitle(label, for: .normal)
                self.actionButton.isHidden = false
            }
        case "friend-joined":
            self.showAvatarButton(with: "friend_image_url")
            self.mainLabel.text = "\(props["friend_name"] as! String)"
            let instanceId = self.instanceId
            Intent.getProfile(identifier: String(props["friend_id"] as! Int64)).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data, self.instanceId == instanceId else {
                    return
                }
                let account = Profile(data: data)
                guard !account.isFollowing else {
                    return
                }
                self.actionButton.setTitle("✚ SUB", for: .normal)
                self.actionButton.isHidden = false
            }
            self.secondaryLabel.text = "joined reaction.cam"
        case "streak":
            self.showAvatarButton()
            self.mainLabel.text = "STREAK 🚨"
            self.secondaryLabel.text = "You’re on a \(props["days"] as! Int)-day posting streak!"
            self.actionButton.setTitle("SHARE", for: .normal)
            self.actionButton.isHidden = false
        case "update-app":
            self.mainLabel.text = "Update Available! 💡"
            self.secondaryLabel.text = "You’re using an old version."
            self.actionButton.setTitle("UPDATE", for: .normal)
            self.actionButton.isHidden = false
        case "content-request":
            assertionFailure("content-request should be handled by RequestNotificationCell")
        default:
            NSLog("WARNING: Unhandled notification type \(notif.type)")
            break
        }
    }

    override func hideCTA() {
        self.actionButton.isHidden = true
    }

    // MARK: - UITableViewCell

    override func awakeFromNib() {
        super.awakeFromNib()
        self.avatarButton.imageView?.contentMode = .scaleAspectFill
        self.avatarButton.layer.cornerRadius = self.avatarButton.bounds.height / 2
        self.contentButton.imageView?.contentMode = .scaleAspectFill
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        if highlighted {
            self.actionButton.setColors()
        }
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        if selected {
            self.actionButton.setColors()
        }
    }

    // MARK: - Actions
    
    @IBAction func actionTapped(_ sender: HighlightButton) {
        self.delegate?.notificationCell(self, receivedTapOn: .action)
    }
    
    @IBAction func avatarTapped(_ sender: UIButton) {
        self.delegate?.notificationCell(self, receivedTapOn: .avatar)
    }
    
    @IBAction func contentTapped(_ sender: UIButton) {
        self.delegate?.notificationCell(self, receivedTapOn: .content)
    }
    
    // MARK: - Private
    
    private func showAvatarButton() {
        if let url = BackendClient.api.session?.imageURL {
            self.avatarButton.af_setImage(for: .normal, url: url, placeholderImage: #imageLiteral(resourceName: "single"))
        } else {
            self.avatarButton.setImage(#imageLiteral(resourceName: "single"), for: .normal)
        }
        self.avatarButton.isHidden = false
    }
    
    @discardableResult
    private func showAvatarButton(with property: String, fallbackToDefault: Bool = true) -> Bool {
        if let url = (self.notif.properties[property] as? String).flatMap(URL.init(string:)) {
            self.avatarButton.af_setImage(for: .normal, url: url, placeholderImage: #imageLiteral(resourceName: "single"))
            self.avatarButton.isHidden = false
            return true
        } else if fallbackToDefault {
            self.avatarButton.setImage(#imageLiteral(resourceName: "single"), for: .normal)
            self.avatarButton.isHidden = false
            return true
        }
        return false
    }

    @discardableResult
    private func showContentButton(with property: String, fallbackToDefault: Bool = false) -> Bool {
        if let url = (self.notif.properties[property] as? String).flatMap(URL.init(string:)) {
            self.contentButton.af_setImageBiased(for: .normal, url: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
            self.contentButton.isHidden = false
            return true
        } else if fallbackToDefault {
            self.contentButton.setImage(#imageLiteral(resourceName: "relatedContent"), for: .normal)
            self.contentButton.isHidden = false
            return true
        }
        return false
    }
}

class RequestNotificationCell: NotificationCell {
    
    @IBOutlet weak var commentLabel: UILabel!
    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var contentImageView: UIImageView!
    @IBOutlet weak var contentTitleLabel: UILabel!
    @IBOutlet weak var verifiedBadge: UIImageView!
    
    override func refresh() {
        self.backgroundView?.backgroundColor = self.notif.seen ? .black : UIColor.uiBlue.withAlphaComponent(0.6)

        let props = self.notif.properties
        if let url = (self.notif.properties["requester_image_url"] as? String).flatMap(URL.init(string:)) {
            self.userImageView.af_setImage(withURL: url)
        }
        self.usernameLabel.text = "@\(props["requester_username"] as! String)"
        self.verifiedBadge.isHidden = (props["requester_verified"] as? Bool) != true
        self.commentLabel.text = props["comment"] as? String ?? "Requested your reaction..."
        if let url = (self.notif.properties["content_thumb_url"] as? String).flatMap(URL.init(string:)) {
            self.contentImageView.af_setImage(withURL: url)
        }
        self.contentTitleLabel.text = props["content_title"] as? String ?? "Loading..."
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        self.backgroundColor = highlighted ? .lightGray : .clear
    }
    
    override func hideCTA() { }
}
