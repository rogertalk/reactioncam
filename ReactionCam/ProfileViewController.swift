import AVFoundation
import GrowingTextView
import iRate
import SafariServices
import StoreKit
import UIKit
import UserNotifications
import XLActionController

class ProfileViewController: UIViewController,
    ChatCellDelegate,
    ContentCollectionDelegate,
    SFSafariViewControllerDelegate,
    UITableViewDelegate,
    UITableViewDataSource,
    UITextViewDelegate
{
    @IBOutlet weak var askRateView: UIView!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var backgroundImageView: UIImageView!
    @IBOutlet weak var buttonsContainer: UIStackView!
    @IBOutlet weak var chatContainer: UIView!
    @IBOutlet weak var chatCTAView: UIView!
    @IBOutlet weak var chatTable: UITableView!
    @IBOutlet weak var communityProfileHeader: UIView!
    @IBOutlet weak var communityImageView: UIImageView!
    @IBOutlet weak var communityUsernameLabel: UILabel!
    @IBOutlet weak var containerScrollView: UIScrollView!
    @IBOutlet weak var contentCollectionView: ContentCollectionView!
    @IBOutlet weak var editProfileButton: HighlightButton!
    @IBOutlet weak var facebookButton: UIButton!
    @IBOutlet weak var findChannelsCTAView: UIView!
    @IBOutlet weak var followersButton: UIButton!
    @IBOutlet weak var followersContainerView: UIView!
    @IBOutlet weak var headerTop: NSLayoutConstraint!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var inputContainer: UIView!
    @IBOutlet weak var inputTextView: GrowingTextView!
    @IBOutlet weak var instagramButton: UIButton!
    @IBOutlet weak var keyboardHeight: NSLayoutConstraint!
    @IBOutlet weak var messageButton: HighlightButton!
    @IBOutlet weak var moreButton: UIButton!
    @IBOutlet weak var originalsContainer: UIView!
    @IBOutlet weak var originalsPreviewTable: UITableView!
    @IBOutlet weak var profileContainer: UIView!
    @IBOutlet weak var rewardsButton: HighlightButton!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var snapchatButton: UIButton!
    @IBOutlet weak var socialMediaContainer: UIStackView!
    @IBOutlet weak var soundcloudButton: UIButton!
    @IBOutlet weak var spotifyButton: UIButton!
    @IBOutlet weak var standardProfileHeader: UIStackView!
    @IBOutlet weak var subscribeButton: HighlightButton!
    @IBOutlet weak var taglineLabel: UILabel!
    @IBOutlet weak var twitterButton: UIButton!
    @IBOutlet weak var urlButton: UIButton!
    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var usernameStackView: UIStackView!
    @IBOutlet weak var usernameTitleLabel: UILabel!
    @IBOutlet weak var verifiedBadgeImage: UIImageView!
    @IBOutlet weak var versionLabel: UILabel!
    @IBOutlet weak var walletButton: UIButton!
    @IBOutlet weak var walletContainerView: UIView!
    @IBOutlet weak var youtubeButton: UIButton!
    @IBOutlet weak var originalsTable: UITableView!
    
    // MARK: - Properties

    var account: Account?

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    var startInChat: Bool = false

    // MARK: - UIViewController

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if self.startInChat {
            self.select(segment: .livechat)
            self.startInChat = false
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let inset = self.headerView.frame.height.rounded()
        self.contentCollectionView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: 80, right: 0)
        self.originalsPreviewTable.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: 80, right: 0)
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

        self.chatTable.dataSource = self
        self.chatTable.delegate = self
        self.chatTable.register(UINib(nibName: "ChatCell", bundle: nil), forCellReuseIdentifier: "ChatCell")
        self.chatTable.register(UINib(nibName: "PaymentCell", bundle: nil), forCellReuseIdentifier: "PaymentCell")
        self.chatTable.rowHeight = UITableViewAutomaticDimension
        self.chatTable.estimatedRowHeight = 40
        self.chatTable.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
        self.chatTable.keyboardDismissMode = .onDrag
        
        self.originalsTable.dataSource = self
        self.originalsTable.delegate = self
        self.originalsTable.register(UINib(nibName: "TopContentCell", bundle: nil), forCellReuseIdentifier: "TopContentCell")
        self.originalsTable.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
        self.originalsTable.keyboardDismissMode = .onDrag
        
        self.originalsPreviewTable.dataSource = self
        self.originalsPreviewTable.delegate = self
        self.originalsPreviewTable.register(UINib(nibName: "SearchResultCell", bundle: nil), forCellReuseIdentifier: "SearchResultCell")
        self.originalsPreviewTable.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)

        
        self.containerScrollView.delegate = self
       
        self.chatContainer.isHidden = true
        self.originalsContainer.isHidden = true
        
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.versionLabel.text = "✌️ reaction.cam \(Bundle.main.version)"

        self.subscribeButton.isHidden = true
        self.editProfileButton.isHidden = true
        
        self.contentCollectionView.contentCollectionDelegate = self

        self.usernameStackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ProfileViewController.usernameTapped)))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        NotificationCenter.default.addObserver(self, selector: #selector(ProfileViewController.keyboardEvent), name: .UIKeyboardWillChangeFrame, object: nil)

        let isCurrentUser = self.account?.isCurrentUser ?? true
        if isCurrentUser {
            // Load latest session data if current user.
            self.account = BackendClient.api.session
        }

        // TODO: Remove "false" here to re-enable this.
        if false, isCurrentUser, let me = BackendClient.api.session {
            self.findChannelsCTAView.isHidden = me.isVerified || me.followingCount >= 3
        } else {
            self.findChannelsCTAView.isHidden = true
        }

        if self.tabBarController == nil {
            self.backButton.isHidden = false
            self.settingsButton.isHidden = true
            if isCurrentUser {
                // in case users tap into their own profile
                self.shareButton.isHidden = false
                self.moreButton.isHidden = true
                self.editProfileButton.isHidden = BackendClient.api.session?.hasBeenOnboarded ?? false
                self.rewardsButton.isHidden = !(BackendClient.api.session?.hasBeenOnboarded ?? false)
            } else {
                self.shareButton.isHidden = true
                self.moreButton.isHidden = false
            }
        } else {
            // Default to own profile if in main navigation.
            guard let session = BackendClient.api.session else {
                NSLog("%@", "WARNING: Could not get current session!")
                return
            }
            self.account = session
            self.updateSettingsButton()
            self.editProfileButton.isHidden = session.hasBeenOnboarded
            self.rewardsButton.isHidden = !session.hasBeenOnboarded
            self.shareButton.isHidden = false
            self.moreButton.isHidden = true

            self.contentCollectionView.reloadData()
            self.askRateView.isHidden = !SettingsManager.shouldAskToRate
            self.walletButton.setTitle("\(session.balance.formattedWithSeparator) Coins", for: .normal)
            self.walletContainerView.isHidden = false
        }

        guard let account = self.account else {
            return
        }

        ContentService.instance.getUserContentList(for: account.id, tag: "reaction") { content, cursor in
            self.originalsPreviewTable.isHidden = !(account.isVerified && content.isEmpty)
            guard Array(self.contentCollectionView.content.prefix(content.count)) != content else {
                return
            }
            self.cursor = cursor
            self.statusIndicatorView.hide()
            self.reactions = content
            self.headerView.setNeedsLayout()
            self.view.setNeedsLayout()
            #if !DEBUG
            // Rate within app itself if this is a super user.
            if
                self.tabBarController != nil &&
                self.reactions.count >= 10 &&
                BackendClient.api.session?.hasBeenOnboarded ?? false, #available(iOS 10.3, *)
            {
                guard let rate = iRate.sharedInstance() else {
                    return
                }
                if !(rate.ratedAnyVersion || rate.declinedAnyVersion) {
                    SKStoreReviewController.requestReview()
                }
            }
            #endif
        }

        self.setUpProfile()

        if !(account is AccountWithExtras) {
            // We need to fetch more data before everything can be filled out.
            Intent.getProfile(identifier: String(account.id)).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    return
                }
                self.account = Profile(data: data)
                self.setUpProfile()
            }
        }

        AppDelegate.applicationActiveStateChanged.addListener(self, method: ProfileViewController.handleAppActiveStateChanged)
        ChatService.instance.disconnected.addListener(self, method: ProfileViewController.handleDisconnected)
        ChatService.instance.joinedChannel.addListener(self, method: ProfileViewController.handleJoinedChannel)
        ChatService.instance.newMessage.addListener(self, method: ProfileViewController.handleNewMessage)
        ChatService.instance.participantsChanged.addListener(self, method: ProfileViewController.handleParticipantsChanged)
        ContentService.instance.contentUpdated.addListener(self, method: ProfileViewController.handleContentUpdated)

        if isCurrentUser {
            PaymentService.instance.purchaseDidComplete.addListener(self, method: ProfileViewController.handlePurchaseDidComplete)
            BackendClient.api.sessionChanged.addListener(self, method: ProfileViewController.handleSessionChanged)
            self.uploads = UploadService.instance.jobs.values.filter { $0.isVisible }
        } else {
            self.isBlocked = self.account?.isBlocked ?? false
            self.uploads = []
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
        NotificationCenter.default.removeObserver(self)
        AppDelegate.applicationActiveStateChanged.removeListener(self)
        ChatService.instance.disconnected.removeListener(self)
        ChatService.instance.joinedChannel.removeListener(self)
        ChatService.instance.newMessage.removeListener(self)
        ChatService.instance.participantsChanged.removeListener(self)
        // Setting uploads to an empty list will prevent updating the UI while it's hidden.
        self.uploads = []
        if let channelId = self.channelId {
            ChatService.instance.leave(channelId: channelId)
        }
    }

    func scrollToTop() {
        self.contentCollectionView.setContentOffset(CGPoint(x: 0.0, y: -self.headerView.frame.height), animated: true)
    }

    // MARK: - Methods

    func isShowing(channel id: String) -> Bool {
        guard let channelId = self.channelId, id == channelId else {
            return false
        }
        return self.selectedSegment == .livechat
    }

    // MARK: - Actions
    
    @IBAction func askRateTapped(_ sender: Any) {
        TabBarController.instance?.showRate(source: "Profile")
        self.askRateView.isHidden = true
        self.headerView.setNeedsLayout()
        self.view.setNeedsLayout()
    }
    
    @IBAction func backTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Back", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.navigationController?.popViewController(animated: true)
    }
    
    @IBAction func editProfileTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Edit", "OwnProfile": self.account?.isCurrentUser ?? false])
        let editProfile = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "EditProfile") as! EditProfileViewController
        self.present(editProfile, animated: true)
    }

    @IBAction func enableLivechatTapped(_ sender: Any) {
        guard let account = self.account, account.isCurrentUser else {
            return
        }
        guard account.followerCount >= 10 else {
            let alert = UIAlertController(
                title: "You need at least 10 subscribers to enable Livechat! 🤠",
                message: "Protip: Subscribe to your favorite creators and they may subscribe to you back!",
                preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
            return
        }
        self.statusIndicatorView.showLoading()
        Intent.updateProfileProperties(properties: ["chat_enabled": true]).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            guard $0.successful else {
                let alert = UIAlertController(
                    title: "Oops!",
                    message: "Something went wrong. Please try again.",
                    preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            self.account = BackendClient.api.session
            self.chatCTAView.hideAnimated()
            self.setUpChat()
        }
    }

    @IBAction func facebookTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Facebook Tapped", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.presentSocialURL(channel: "facebook")
    }

    @IBAction func findChannelsTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Find Channels (Empty CTA)"])
        TabBarController.select(tab: .search, source: "Profile")
    }
    
    @IBAction func followersTapped(_ sender: Any) {
        guard let account = self.account else {
            return
        }
        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "AccountList") as! AccountListViewController
        vc.type = .followers(account: account)
        self.navigationController!.pushViewController(vc, animated: true)
    }

    @IBAction func instagramTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Instagram Tapped", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.presentSocialURL(channel: "instagram")
    }

    @IBAction func messageTapped(_ sender: Any) {
        Logging.debug("Profile Action", ["Action": "Message", "OwnProfile": self.account?.isCurrentUser ?? false])
        guard let id = self.account?.id else {
            return
        }
        self.openMessages(accountId: id)
    }

    @IBAction func moreTapped(_ sender: Any) {
        self.inputTextView.resignFirstResponder()
        guard let account = self.account as? AccountWithExtras else {
            return
        }

        Logging.debug("Profile Action", ["Action": "More", "OwnProfile": self.account?.isCurrentUser ?? false])

        let title = "🎞 \(account.contentCount.description)"
        let sheet = ActionSheetController(title: title)
        sheet.addAction(Action("Direct Message 📩", style: .default) { _ in
            Logging.log("Profile More", ["Action": "Direct Message"])
            guard let id = self.account?.id else {
                return
            }
            self.openMessages(accountId: id)
        })
        sheet.addAction(Action("Request Reaction", style: .default) { _ in
            Logging.log("Profile More", ["Action": "Request Reaction"])
            let pickSource = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "PickSource") as! PickSourceViewController
            pickSource.mode = .request(account: account)
            pickSource.modalPresentationStyle = .overCurrentContext
            pickSource.modalTransitionStyle = .crossDissolve
            self.present(pickSource, animated: true)
        })
        sheet.addAction(Action("Share Channel", style: .default) { _ in
            Logging.log("Profile More", ["Action": "Share"])
            let copy = SettingsManager.shareChannelCopy(account: account)
            let vc = UIActivityViewController(activityItems: [DynamicActivityItem(copy)], applicationActivities: nil)
            vc.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
            vc.configurePopover(sourceView: self.moreButton)
            self.present(vc, animated: true)
        })
        if let account = self.account as? AccountWithFollowState {
            if account.isFollowing {
                sheet.addAction(Action("Unsubscribe", style: .destructive) { _ in
                    Logging.log("Profile More", ["Action": "Unfollow", "OwnProfile": false])
                    let subsheet = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .actionSheet)
                    subsheet.addAction(UIAlertAction(title: "Yes, unsubscribe", style: .destructive) { _ in
                        Logging.log("Profile More", ["Action": "UnfollowYes", "OwnProfile": false])
                        self.toggleFollowing(account: account)
                        self.followersCount -= 1
                    })
                    subsheet.addCancel() {
                        Logging.log("Profile Action", ["Action": "UnfollowNo", "OwnProfile": false])
                    }
                    subsheet.configurePopover(sourceView: self.moreButton)
                    self.present(subsheet, animated: true)
                })
            } else {
                sheet.addAction(Action("Subscribe", style: .default) { _ in
                    Logging.log("Profile More", ["Action": "Follow", "OwnProfile": false])
                    self.toggleFollowing(account: account)
                })
            }
        }
        if self.isBlocked {
            sheet.addAction(Action("Unblock", style: .destructive) { _ in
                Logging.log("Profile More", ["Action": "Unblock User"])
                self.statusIndicatorView.showLoading()
                Intent.unblockUser(identifier: String(account.id)).perform(BackendClient.api) {
                    guard $0.successful else {
                        self.statusIndicatorView.hide()
                        let alert = UIAlertController(title: "Oops!", message: "Something went wrong. Please try again.", preferredStyle: .alert)
                        alert.addCancel(title: "OK")
                        self.present(alert, animated: true)
                        return
                    }
                    self.statusIndicatorView.showConfirmation(title: "Unblocked")
                    // Reload data to account for newly unblocked user.
                    ContentService.instance.loadFeaturedContent()
                    ContentService.instance.loadRecentContent()
                    self.isBlocked = false
                }
            })
        } else {
            sheet.addAction(Action("Block & Report", style: .destructive) { _ in
                Logging.log("Profile More", ["Action": "Block User"])
                self.presentBlockAlert(for: account.id, username: account.username)
            })
        }
        sheet.addCancel()
        sheet.configurePopover(sourceView: self.moreButton)
        self.present(sheet, animated: true)
    }

    @IBAction func originalsTapped(_ sender: Any) {
        self.select(segment: .originals)
    }
    
    @IBAction func rewardsTapped(_ sender: Any) {
        guard let account = self.account as? AccountWithExtras else {
            return
        }
        if account.isCurrentUser, let tiers = account.properties["tiers"] as? [[String: Any]], tiers.isEmpty {
            guard let editRewards = Bundle.main.loadNibNamed("EditRewardsViewController", owner: nil, options: nil)?.first as? EditRewardsViewController else {
                return
            }
            self.present(editRewards, animated: true)
            return
        }
        Logging.log("Profile Action", ["Action": "Rewards", "OwnProfile": self.account?.isCurrentUser ?? false])
        TabBarController.showRewards(for: account)
    }

    @IBAction func snapchatTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Snapchat Tapped", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.presentSocialURL(channel: "snapchat")
    }

    @IBAction func sendTapped(_ sender: Any) {
        Logging.log("Livechat Action",  ["Result": "SendButton"])
        self.sendMessage()
    }

    @IBAction func settingsTapped(_ button: UIButton) {
        self.inputTextView.resignFirstResponder()
        Logging.log("Profile Action", ["Action": "Settings", "OwnProfile": self.account?.isCurrentUser ?? false])
        guard let session = BackendClient.api.session else {
            return
        }

        let title = "🎞 \(session.contentCount.formattedWithSeparator) videos"
        let sheet = ActionSheetController(title: title)
        if self.showEnableNotifications {
            sheet.addAction(Action("👉 Enable Notifications", style: .destructive) { _ in
                Logging.log("Profile Settings", ["Action": "Enable Notifications"])
                AppDelegate.requestNotificationPermissions(presentAlertWith: self, source: "ProfileView") { _ in
                    self.updateSettingsButton()
                }
            })
        }
        sheet.addAction(Action("Your Subscriptions", style: .default) { _ in
            Logging.log("Profile Settings", ["Action": "Subscriptions"])
            let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "AccountList") as! AccountListViewController
            vc.type = .following(account: session)
            self.navigationController!.pushViewController(vc, animated: true)
        })
        sheet.addAction(Action("\(session.balance.formattedWithSeparator) Coins", style: .default) { _ in
            Logging.log("Profile Settings", ["Action": "Coins"])
            self.showWallet()
        })
        sheet.addAction(Action(session.hasBeenOnboarded ? "Account" : "👉 Account", style: session.hasBeenOnboarded ? .default : .destructive) { _ in
            Logging.log("Profile Settings", ["Action": "Account"])
            let editProfile = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "EditProfile") as! EditProfileViewController
            self.present(editProfile, animated: true)

        })
        sheet.addAction(Action("Terms of Use", style: .default) { _ in
            Logging.log("Profile Settings", ["Action": "Terms of Use"])
            let vc = SFSafariViewController(url: URL(string: "https://www.reaction.cam/terms")!)
            self.webController = vc
            vc.preferredBarTintColor = UIColor.uiBlack
            vc.preferredControlTintColor = UIColor.white
            vc.delegate = self
            self.present(vc, animated: true)
        })
        sheet.addAction(Action("Support", style: .default) { _ in
            Logging.log("Profile Settings", ["Action": "Feedback"])
            HelpViewController.showHelp(presenter: self)
        })
        sheet.addCancel()
        sheet.configurePopover(sourceView: button)
        self.present(sheet, animated: true)
    }

    @IBAction func shareTapped(_ sender: UIButton) {
        Logging.log("Profile Action", ["Action": "Open Channel Link", "OwnProfile": self.account?.isCurrentUser ?? false])
        guard let account = self.account else {
            return
        }
        UIApplication.shared.open(URL(string: SettingsManager.getChannelURL(username: account.username))!, options: [:])
    }

    @IBAction func soundcloudTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "SoundCloud Tapped", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.presentSocialURL(channel: "soundcloud")
    }

    @IBAction func spotifyTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Spotify Tapped", "OwnProfile": self.account?.isCurrentUser ?? false])
        guard
            let account = self.account as? AccountWithExtras,
            let value = (account.properties["spotify"] as? String)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            let url = URL(string: value)
            else { return }
        UIApplication.shared.open(url, options: [:])
    }

    @IBAction func subscribeTapped(_ sender: HighlightButton) {
        guard let account = self.account as? AccountWithFollowState else {
            return
        }
        if account.isFollowing {
            Logging.log("Profile Action", ["Action": "Unfollow", "OwnProfile": false])
            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Unsubscribe", style: .destructive) { _ in
                Logging.log("Profile Action", ["Action": "UnfollowYes", "OwnProfile": false])
                self.toggleFollowing(account: account)
                self.followersCount -= 1
            })
            sheet.addCancel() {
                Logging.log("Profile Action", ["Action": "UnfollowNo", "OwnProfile": false])
            }
            sheet.configurePopover(sourceView: sender)
            self.present(sheet, animated: true)
        } else {
            Logging.log("Profile Action", ["Action": "Follow", "OwnProfile": false])
            self.toggleFollowing(account: account)
            self.followersCount += 1
            self.followersContainerView.pulse()
            self.ensureLoggedIn()
        }
    }

    @IBAction func tabChanged(_ sender: UISegmentedControl) {
        self.select(segment: self.segments[sender.selectedSegmentIndex])
    }

    @IBAction func twitterTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Twitter Tapped", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.presentSocialURL(channel: "twitter")
    }

    @IBAction func urlTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Link", "OwnProfile": self.account?.isCurrentUser ?? false])
        guard let account = self.account as? AccountWithExtras else {
            return
        }

        guard let url = (account.properties["url"] as? String).flatMap(URL.init(string:)) else {
            return
        }

        guard Recorder.instance.composer != nil else {
            UIApplication.shared.open(url, options: [:])
            return
        }

        TabBarController.showCreate(url: url, ref: nil, relevantUsername: account.username,
                                    source: "Profile URL Tapped")
    }

    @IBAction func userImageTapped(_ sender: UITapGestureRecognizer) {
        guard self.account?.isCurrentUser ?? true else {
            return
        }
        Logging.log("Profile Action", ["Action": "Picture", "OwnProfile": self.account?.isCurrentUser ?? false])
        let editProfile = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "EditProfile") as! EditProfileViewController
        editProfile.action = .updatePicture
        self.present(editProfile, animated: false) // Not animated because Edit Profile will present image picker.
    }

    @objc private dynamic func usernameTapped() {
        Logging.log("Profile Action", ["Action": "Username Tapped", "OwnProfile": self.account?.isCurrentUser ?? false, "Verified": self.account?.isVerified ?? false])
        guard let account = self.account, !account.isCurrentUser else {
            let editProfile = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "EditProfile") as! EditProfileViewController
            self.present(editProfile, animated: true)
            return
        }
        if account.isVerified {
            let alert = UIAlertController(title: "Verified Artist ", message: "@\(account.username) is a verified artist on Reaction.cam", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Learn more", style: .default) { _ in
                Logging.log("Verified Dialog Profile", ["Action": "Learn more"])
                UIApplication.shared.open(SettingsManager.helpArtistsURL, options: [:])
            })
            let cta = UIAlertAction(title: "OK", style: .default) { _ in
                Logging.log("Verified Dialog Profile", ["Action": "OK"])
            }
            alert.addAction(cta)
            alert.preferredAction = cta
            self.present(alert, animated: true)
        }
    }

    @IBAction func walletTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "Wallet Tapped", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.showWallet()
    }

    @IBAction func youtubeTapped(_ sender: Any) {
        Logging.log("Profile Action", ["Action": "YouTube Tapped", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.presentSocialURL(channel: "youtube")
    }

    // MARK: - ChatCellDelegate

    func chatCell(_ cell: ChatCell, didTapAccount account: MessageAccount) {
        let isHost = self.account?.isCurrentUser ?? false
        Logging.log("Livechat Action", [
            "Result": "Account Tapped",
            "AccountId": account.id,
            "OwnProfile": isHost])
        let sheet = UIAlertController(title: "@\(account.username)", message: nil, preferredStyle: .actionSheet)
        sheet.configurePopover(sourceView: cell)
        sheet.addAction(UIAlertAction(title: "Go to channel", style: .default) { _ in
            Logging.log("Livechat Account Sheet", ["Option": "GoToProfile"])
            guard account.id != self.account?.id else {
                self.select(segment: .profile)
                return
            }
            self.statusIndicatorView.showLoading()
            Intent.getProfile(identifier: String(account.id)).perform(BackendClient.api) {
                self.statusIndicatorView.hide()
                guard $0.successful, let data = $0.data else {
                    return
                }
                TabBarController.select(account: Profile(data: data))
            }
        })
        sheet.addAction(UIAlertAction(title: "Send private message", style: .default) { _ in
            Logging.log("Livechat Account Sheet", ["Option": "PrivateMessage"])
            self.openMessages(accountId: account.id)
        })
        sheet.addAction(UIAlertAction(title: "Block @\(account.username)", style: .destructive) { _ in
            Logging.log("Livechat Account Sheet", ["Option": "Block"])
            self.presentBlockAlert(for: account.id, username: account.username) { didBlock in
                guard let channelId = self.channelId, didBlock && isHost else {
                    return
                }
                ChatService.instance.kick(accountId: account.id, from: channelId)
            }
        })
        sheet.addCancel()
        self.present(sheet, animated: true)
    }

    func chatCell(_ cell: ChatCell, didTapReplyFor account: MessageAccount) {
        if let text = self.inputTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            self.inputTextView.text = "\(text) @\(account.username) "
        } else {
            self.inputTextView.text = "@\(account.username) "
        }
        self.inputTextView.becomeFirstResponder()
    }

    // MARK: - ContentCollectionDelegate

    func contentCollection(_ contentCollectionView: UICollectionView, didScrollTo offset: CGPoint) {
        self.headerTop.constant = (-offset.y - contentCollectionView.contentInset.top)
        guard
            !self.isRequestingNextPage,
            let account = self.account,
            let cursor = self.cursor,
            contentCollectionView.contentSize.height - offset.y < contentCollectionView.bounds.height
            else { return }
        self.isRequestingNextPage = true
        ContentService.instance.getUserContentList(for: account.id, tag: "reaction", cursor: cursor) { content, cursor in
            self.cursor = cursor
            self.contentCollectionView.content.append(contentsOf: content)
            self.isRequestingNextPage = false
        }
    }

    func contentCollection(_ contentCollectionView: UICollectionView, didSelectUpload upload: UploadJob, at indexPath: IndexPath) {
        let source = "Upload Menu (ProfileViewController)"
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
    
    // MARK: - SFSafariViewControllerDelegate
    
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        self.webController = nil
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        switch scrollView {
        case self.containerScrollView:
            let width = self.view.bounds.width
            if scrollView.contentOffset.x >= width * 2, self.segmentedControl.numberOfSegments > 1 {
                self.segmentedControl.selectedSegmentIndex = 2
            } else if scrollView.contentOffset.x >= width, self.segmentedControl.numberOfSegments > 0 {
                self.segmentedControl.selectedSegmentIndex = 1
            } else {
                self.segmentedControl.selectedSegmentIndex = 0
            }
        default:
            break
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == self.originalsPreviewTable else {
            return
        }
        self.headerTop.constant = (-scrollView.contentOffset.y - self.originalsPreviewTable.contentInset.top)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        switch scrollView {
        case self.containerScrollView:
            self.view.endEditing(true)
        default:
            break
        }
    }

    // MARK: - UITextViewDelegate
    
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
        Logging.log("Livechat Action", ["Result": "SendMessage", "OwnProfile": self.account?.isCurrentUser ?? false])
        self.sendMessage()
        return false
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        switch tableView {
        case self.chatTable:
            return 1
        case self.originalsPreviewTable, self.originalsTable:
            return 1
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch tableView {
        case self.chatTable:
            let entry = self.chatHistory[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "ChatCell") as! ChatCell
            cell.delegate = self
            cell.entry = entry
            cell.messageLabel.text = entry.message.text
            let shouldShowHeader: Bool
            let timeLabel = entry.message.timestamp.timeLabel
            if indexPath.row == 0 {
                shouldShowHeader = true
            } else {
                let prevEntry = self.chatHistory[indexPath.row - 1]
                let diff = entry.message.timestamp.timeIntervalSince(prevEntry.message.timestamp)
                let prevTimeLabel = prevEntry.message.timestamp.timeLabel
                shouldShowHeader = prevEntry.account.id != entry.account.id || (diff > 3600 && timeLabel != prevTimeLabel)
            }
            if shouldShowHeader {
                cell.userImageView.af_setImage(withURL: entry.account.imageURL)
                cell.usernameLabel.text = entry.account.username
                let isHost = entry.account.id == self.account?.id
                cell.usernameLabel.textColor = isHost ? .uiYellow : .white
                cell.timestampLabel.text = "\(isHost ? "(HOST)  " : "")\(timeLabel)"
            } else {
                cell.headerView.isHidden = true
                cell.userImageView.isHidden = true
            }
            return cell
        case self.originalsPreviewTable:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell") as! SearchResultCell
            let original = self.originals[indexPath.row]
            if let url = original.thumbnailURL {
                cell.contentSuggestionView.thumbnailButton.af_setImage(for: .normal, url: url)
            }
            cell.contentSuggestionView.titleLabel.text = original.title
            cell.contentSuggestionView.reactionsLabel.text = "\(original.relatedCount) reactions"
            return cell
        case self.originalsTable:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TopContentCell") as! TopContentCell
            let original = self.originals[indexPath.row]
            cell.originalContentView.content = original
            cell.originalContentView.source = "Profile"
            return cell
        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch tableView {
        case self.chatTable:
            return self.chatHistory.count
        case self.originalsPreviewTable, self.originalsTable:
            return self.originals.count
        default:
            return 0
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard tableView == self.originalsPreviewTable || tableView == self.originalsTable else {
            return
        }
        TabBarController.select(originalContent: self.originals[indexPath.row], source: "Profile Row")
        Logging.log("Profile Originals Tab Select", [
            "Index": String(indexPath.row)]
        )
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch tableView {
        case self.chatTable:
            return UITableViewAutomaticDimension
        case self.originalsPreviewTable:
            return 80
        case self.originalsTable:
            return OriginalContentView.defaultHeight
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch tableView {
        case self.originalsPreviewTable, self.originalsTable:
            return true
        default:
            return false
        }
    }

    // MARK: - Private

    private enum Segment {
        case livechat
        case originals
        case profile
    }

    private var channelId: String? {
        guard let account = self.account as? AccountWithExtras, account.hasChatEnabled else {
            return nil
        }
        return String(account.id)
    }

    private var chatAccounts = [Int64: MessageAccount]()
    private var chatHistory = [ChatService.Channel.Entry]()
    private var cursor: String? = nil
    private var didAskForUsername = false

    private var followersCount: Int = 0 {
        didSet {
            guard let account = self.account as? AccountWithExtras else {
                return
            }
            if let followersTitle = account.properties["followers_title"] as? String, !followersTitle.isEmpty {
                self.followersButton.setTitle(self.followersCount.countLabelShort + " " + followersTitle, for: .normal)
            } else {
                self.followersButton.setTitle(self.followersCount.countLabelShort + " Subscribers", for: .normal)
            }
        }
    }

    private var isBlocked = false
    private var isRequestingNextPage = false

    private var originals = [OriginalContent]() {
        didSet {
            self.originalsPreviewTable.reloadData()
            self.originalsTable.reloadData()
        }
    }

    private var reactions = [Content]() {
        didSet {
            self.updateProfileTitle()
            self.contentCollectionView.content = self.reactions
        }
    }

    private var segments: [Segment] = [.profile] {
        didSet {
            self.updateSegments()
        }
    }

    private var selectedSegment: Segment {
        return self.segments[self.segmentedControl.selectedSegmentIndex]
    }

    private var showEnableNotifications = false
    private var statusIndicatorView: StatusIndicatorView!

    private var uploads = [UploadJob]() {
        didSet {
            self.contentCollectionView.uploads = self.uploads
        }
    }
    
    private var webController: SFSafariViewController?

    private func ensureLoggedIn() {
        guard !self.didAskForUsername && BackendClient.api.session?.hasBeenOnboarded == false else {
            return
        }
        let alert = UIAlertController(title: "Awesome!", message: "Now create a username so people can find and subscribe to your channel.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Create Username 😎", style: .default) { _ in
            Logging.log("Create Username Dialog Profile", ["Action": "Sign Up"])
            TabBarController.select(tab: .profile, source: "SubscribeSignUpCTA")
        })
        alert.addAction(UIAlertAction(title: "I'll do it later", style: .destructive) { _ in
            Logging.log("Create Username Dialog Profile", ["Action": "Later"])
        })
        self.present(alert, animated: true)
        self.didAskForUsername = true
    }

    private func formatCountLabel(number: Int) -> String {
        if number >= 1000000 {
            return "\(String(format: "%.01f", Float(number) / 1000000.0))M"
        } else if number >= 100000 {
            return "\(String(format: "%.0f", Float(number) / 1000.0))K"
        } else if number >= 1000 {
            return "\(String(format: "%.01f", Float(number) / 1000.0))K"
        } else {
            return String(number)
        }
    }

    private func handleAppActiveStateChanged(active: Bool) {
        if active {
            self.setUpChat()
        }
    }

    private func handleContentUpdated(content: Content) {
        guard content.creator.id == self.account?.id else {
            return
        }
        if let index = self.reactions.index(where: { $0.id == content.id }) {
            self.reactions[index].update(with: content)
        } else if content.tags.contains("reaction") {
            self.reactions.insert(content, at: 0)
        }
        self.contentCollectionView.reloadData()
    }

    private func handleDisconnected() {
        self.updateSegments()
    }

    private func handleNewMessage(channel: ChatService.Channel, entry: ChatService.Channel.Entry) {
        guard channel.id == self.channelId else {
            return
        }
        self.chatHistory = channel.history
        self.chatTable.reloadData()
        self.view.layoutIfNeeded()
        self.scrollChatToBottom(animated: false)
        if !entry.account.isCurrentUser {
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        }
    }

    private func handleJoinedChannel(channel: ChatService.Channel) {
        guard channel.id == self.channelId else {
            return
        }
        self.reloadChatData(with: channel)
        self.scrollChatToBottom(animated: false)
    }

    private func handleParticipantsChanged(channel: ChatService.Channel) {
        guard channel.id == self.channelId else {
            return
        }
        self.chatAccounts = channel.accounts
        self.updateSegments()
    }

    private func handlePurchaseDidComplete() {
        self.updateAccountExtras()
        self.updateVisibleUI()
    }

    private func handleSessionChanged() {
        self.updateProfileInfo()
        self.updateAccountExtras()
        self.updateVisibleUI()
    }

    @objc private dynamic func keyboardEvent(notification: NSNotification) {
        guard let keyboardHeight = self.keyboardHeight, let view = self.view else {
            return
        }
        let safeY: CGFloat
        if #available(iOS 11.0, *) {
            safeY = self.view.safeAreaInsets.bottom
        } else {
            safeY = 0
        }
        let info = notification.userInfo!
        let frame = info[UIKeyboardFrameEndUserInfoKey] as! CGRect
        let targetY = max(view.bounds.height - frame.minY - safeY, 0)
        view.layoutIfNeeded()
        let duration = (info[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut, animations: {
            keyboardHeight.constant = targetY
            view.layoutIfNeeded()
        }) { _ in
            if keyboardHeight.constant > 0 {
                self.scrollChatToBottom()
            }
        }
    }

    private func openMessages(accountId: Int64) {
        guard let messages = Bundle.main.loadNibNamed("MessagesViewController", owner: nil)?.first as? MessagesViewController else {
            return
        }
        self.statusIndicatorView.showLoading()
        MessageService.instance.createThread(identifier: String(accountId)) { thread, error in
            self.statusIndicatorView.hide()
            guard let thread = thread, error == nil else {
                let alert = UIAlertController(title: "Oops!", message: "An error occured while opening messages. Please try again later!", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            messages.thread = thread
            self.navigationController?.pushViewController(messages, animated: true)
        }
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
                    let alert = UIAlertController(title: "Oops!", message: "Something went wrong. Please try again.", preferredStyle: .alert)
                    alert.addCancel(title: "OK")
                    self.present(alert, animated: true)
                    callback?(false)
                    return
                }
                self.statusIndicatorView.showConfirmation(title: "Blocked")
                // Reload data to account for newly blocked user.
                ContentService.instance.loadFeaturedContent()
                ContentService.instance.loadRecentContent()
                if accountId == self.account?.id {
                    self.isBlocked = true
                    if let channelId = self.channelId {
                        ChatService.instance.leave(channelId: channelId)
                    }
                }
                callback?(true)
            }
        })
        alert.addCancel() {
            Logging.log("Block User", ["Action": "Cancel"])
            callback?(false)
        }
        self.present(alert, animated: true)
    }

    private func presentSocialURL(channel: String) {
        guard let account = self.account as? AccountWithExtras else {
            return
        }

        var url: URL? = nil
        if let value = (account.properties[channel] as? String)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !value.isEmpty {
            var maybeUrl = value
            for prefix in ["http://", "https://"] {
                if maybeUrl.lowercased().hasPrefix(prefix) {
                    maybeUrl = String(maybeUrl.dropFirst(prefix.count))
                    break
                }
            }
            // Check if the user entered a valid domain
            let domains: [String: [String]] = [
                "facebook": ["facebook.com", "www.facebook.com", "m.facebook.com", "fb.com", "www.fb.com"],
                "instagram": ["instagram.com", "www.instagram.com"],
                "snapchat": ["snapchat.com", "www.snapchat.com"],
                "soundcloud": ["soundcloud.com", "m.soundcloud.com"],
                "twitter": ["twitter.com", "www.twitter.com", "mobile.twitter.com", "m.twitter.com"],
                "youtube": ["youtube.com", "www.youtube.com", "m.youtube.com"],
                ]
            let maybeUrlLowercased = maybeUrl.lowercased()
            for domain in domains[channel]! {
                if maybeUrlLowercased.hasPrefix(domain) {
                    url = URL(string: "https://\(maybeUrl)")
                    break
                }
            }
            // Fallback to username
            if url == nil {
                let username = value.hasPrefix("@") ? String(value.dropFirst()) : value
                let prefix: [String: String] = [
                    "facebook": "https://www.facebook.com/",
                    "instagram": "https://instagram.com/",
                    "snapchat": "https://snapchat.com/add/",
                    "soundcloud": "https://soundcloud.com/",
                    "twitter": "https://twitter.com/",
                    "youtube": "https://youtube.com/results?sp=EgIQAlAU&search_query=",
                    ]
                url = URL(string: prefix[channel]! + (username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
            }
        }
        
        if let url = url {
            let vc = SFSafariViewController(url: url)
            self.webController = vc
            vc.delegate = self
            self.present(vc, animated: true)
        }
    }

    private func reloadChatData(with channel: ChatService.Channel) {
        self.chatAccounts = channel.accounts
        self.updateSegments()
        self.chatHistory = channel.history
        self.chatTable.reloadData()
        self.view.layoutIfNeeded()
    }

    private func sendMessage() {
        let text = self.inputTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let channelId = self.channelId else {
            return
        }
        ChatService.instance.send(to: channelId, text: text)
        self.inputTextView.text = ""
        self.sendButton.isHidden = true
    }
    
    private func scrollChatToBottom(animated: Bool = true) {
        let messageCount = self.chatHistory.count
        guard messageCount > 0 else {
            return
        }
        let indexPath = IndexPath(row: messageCount - 1, section: 0)
        self.chatTable.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    private func select(segment: Segment) {
        guard let i = self.segments.index(of: segment) else {
            return
        }
        self.segmentedControl.selectedSegmentIndex = i
        let offset = CGPoint(x: self.view.bounds.width * CGFloat(i), y: 0)
        self.containerScrollView.setContentOffset(offset, animated: true)
        if segment != .livechat {
            self.view.endEditing(true)
        }
    }

    private func setUpChat() {
        guard let session = BackendClient.api.session, let channelId = self.channelId else {
            return
        }
        if let channel = ChatService.instance.channels[channelId] {
            self.reloadChatData(with: channel)
        }
        ChatService.instance.connect(session: session)
        ChatService.instance.join(channelId: channelId)
    }

    private func setUpProfile() {
        self.updateFollowingState()
        self.updateProfileInfo()
        self.updateAccountExtras()
        self.updateVisibleUI()
        self.setUpChat()
        self.contentCollectionView.pinnedContent = (self.account as? AccountWithExtras)?.pinnedContent
        self.headerView.setNeedsLayout()
        self.view.setNeedsLayout()
    }

    private func showWallet() {
        guard let session = BackendClient.api.session else {
            return
        }
        let sheet = ActionSheetController(title: "Balance: \(session.balance.formattedWithSeparator) Coins\nNot enough to withdraw.")
        sheet.addAction(Action("Buy Coins", style: .default) { _ in
            Logging.log("Profile Wallet Action", ["Action": "Get Coins"])
            PaymentService.instance.showBuyCoins()
        })
        sheet.addAction(Action("Earn Coins", style: .default) { _ in
            Logging.log("Profile Wallet Action", ["Action": "Earn Coins"])
            if let tabBarController = self.tabBarController {
                tabBarController.selectedIndex = 0
            }
        })
        sheet.addAction(Action("Learn more", style: .default) { _ in
            Logging.log("Profile Wallet Action", ["Action": "Learn More"])
            UIApplication.shared.open(SettingsManager.helpCoinsURL, options: [:])
        })
        sheet.addCancel() {
            Logging.log("Profile Wallet Action", ["Action": "Cancel"])
        }
        self.present(sheet, animated: true)
    }

    private func title(for segment: Segment) -> String {
        switch segment {
        case .livechat:
            if self.chatAccounts.count > 0 {
                return "LIVECHAT (\(self.chatAccounts.count))"
            } else {
                return "LIVECHAT"
            }
        case .originals:
            return "ORIGINALS"
        case .profile:
            return "PROFILE"
        }
    }

    private func toggleFollowing(account: AccountWithFollowState) {
        self.subscribeButton.isLoading = true
        self.messageButton.isLoading = true
        account.toggleFollowing { _ in
            self.subscribeButton.isLoading = false
            self.messageButton.isLoading = false
            self.updateFollowingState()
        }
    }

    private func updateSettingsButton() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard let session = BackendClient.api.session else {
                    return
                }
                self.showEnableNotifications = settings.authorizationStatus != .authorized
                if !self.showEnableNotifications, session.hasBeenOnboarded {
                    self.settingsButton.setTitleColor(.white, for: .normal)
                } else {
                    self.settingsButton.setTitleColor(.red, for: .normal)
                }
            }
        }
    }

    private func updateAccountExtras() {
        guard let account = self.account as? AccountWithExtras else {
            return
        }

        if account.isVerified || account.status == "unclaimed" {
            Intent.getProfileOriginalList(identifier: String(account.id), limit: nil, cursor: nil).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                    return
                }
                self.originals = data.compactMap(OriginalContent.init)
            }
        }
    }

    private func updateFollowingState() {
        guard let account = self.account, !account.isCurrentUser else {
            self.subscribeButton.isHidden = true
            self.rewardsButton.setTitle("🎁 REWARDS", for: .normal)
            return
        }
        guard let accountWithFollow = account as? AccountWithFollowState else {
            self.subscribeButton.isHidden = true
            self.rewardsButton.setTitle("🎁 REWARDS", for: .normal)
            return
        }
        if accountWithFollow.isFollowing {
            self.subscribeButton.isHidden = true
            self.rewardsButton.setTitle("🎁 REWARDS", for: .normal)
            self.messageButton.isHidden = false
        } else {
            self.subscribeButton.isHidden = false
            self.rewardsButton.setTitle("🎁", for: .normal)
            self.messageButton.isHidden = true
        }
    }

    private func updateProfileInfo() {
        self.updateProfileTitle()
        guard let account = self.account as? AccountWithExtras else {
            return
        }
        self.followersCount = account.followerCount
        let bio = account.properties["bio"] as? String ?? SettingsManager.defaultBio
        if !bio.isEmpty {
            self.taglineLabel.text = bio
            self.taglineLabel.isHidden = false
        } else {
            self.taglineLabel.isHidden = true
        }
        if let url = account.imageURL {
            self.userImageView.af_setImage(withURL: url, placeholderImage: UIImage(named: "single"))
            self.backgroundImageView.af_setImage(withURL: url, placeholderImage: UIImage(named: "single"))
            self.communityImageView.af_setImage(withURL: url, placeholderImage: UIImage(named: "single"))
        }
    }

    private func updateProfileTitle() {
        let username: String
        guard let account = self.account else {
            username = "Set username"
            self.usernameTitleLabel.text = username
            self.usernameTitleLabel.alpha = 0.5
            self.communityUsernameLabel.text = username
            self.verifiedBadgeImage.isHidden = true
            return
        }
        if account.isCurrentUser && !(BackendClient.api.session?.hasBeenOnboarded ?? false) {
            username = "Set username"
            self.usernameTitleLabel.alpha = 0.5
        } else {
            username = account.displayName == account.username ? "@\(account.username)" : account.displayName
            self.usernameTitleLabel.alpha = 1
        }
        self.usernameTitleLabel.text = username
        self.communityUsernameLabel.text = username
        self.verifiedBadgeImage.isHidden = !account.isVerified
    }

    private func updateSegments() {
        let control = self.segmentedControl!
        while control.numberOfSegments > self.segments.count {
            control.removeSegment(at: control.numberOfSegments - 1, animated: false)
        }
        while control.numberOfSegments < self.segments.count {
            let i = control.numberOfSegments
            let title = self.title(for: self.segments[i])
            control.insertSegment(withTitle: title, at: i, animated: false)
        }
        for (i, segment) in self.segments.enumerated() {
            let title = self.title(for: segment)
            if control.titleForSegment(at: i) != title {
                control.setTitle(title, forSegmentAt: i)
            }
        }
        control.isHidden = self.segments.count < 2
    }

    private func updateVisibleUI() {
        guard let a = self.account else {
            return
        }

        self.facebookButton.isHidden = true
        self.instagramButton.isHidden = true
        self.originalsContainer.isHidden = true
        self.snapchatButton.isHidden = true
        self.socialMediaContainer.isHidden = true
        self.soundcloudButton.isHidden = true
        self.spotifyButton.isHidden = true
        self.twitterButton.isHidden = true
        self.urlButton.isHidden = true
        self.youtubeButton.isHidden = true

        // Set up the segments (tabs) on the profile.
        var segments = [Segment]()

        if a.status == "unclaimed" {
            self.buttonsContainer.isHidden = true
            self.communityProfileHeader.isHidden = false
            self.standardProfileHeader.isHidden = true
            self.moreButton.isHidden = true
            self.shareButton.isHidden = false
            self.followersContainerView.isHidden = true
            self.profileContainer.isHidden = true
        } else {
            self.buttonsContainer.isHidden = false
            self.communityProfileHeader.isHidden = true
            self.standardProfileHeader.isHidden = false
            self.followersContainerView.isHidden = false
            self.profileContainer.isHidden = false
            segments.append(.profile)
        }

        if a.isVerified || a.status == "unclaimed" {
            self.originalsContainer.isHidden = false
            segments.append(.originals)
        }

        if a.isCurrentUser {
            self.chatContainer.isHidden = false
            segments.append(.livechat)
        }

        // From this point on, the account must have extras.
        guard let aa = a as? AccountWithExtras else {
            self.segments = segments
            return
        }

        if !a.isCurrentUser && aa.hasChatEnabled {
            segments.append(.livechat)
        }
        self.segments = segments

        if a.isCurrentUser {
            self.chatCTAView.isHidden = aa.hasChatEnabled
        } else {
            self.chatContainer.isHidden = !aa.hasChatEnabled
        }

        if let url = aa.properties["url"] as? String, !url.isEmpty {
            self.urlButton.isHidden = false
            self.urlButton.setTitle(url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""), for: .normal)
        }
        if let facebook = aa.properties["facebook"] as? String, !facebook.isEmpty {
            self.facebookButton.isHidden = false
            self.socialMediaContainer.isHidden = false
        }
        if let youTube = aa.properties["youtube"] as? String, !youTube.isEmpty {
            self.youtubeButton.isHidden = false
            self.socialMediaContainer.isHidden = false
        }
        if let spotify = aa.properties["spotify"] as? String, !spotify.isEmpty {
            self.spotifyButton.isHidden = false
            self.socialMediaContainer.isHidden = false
        }
        if let soundcloud = aa.properties["soundcloud"] as? String, !soundcloud.isEmpty {
            self.soundcloudButton.isHidden = false
            self.socialMediaContainer.isHidden = false
        }
        if let instagram = aa.properties["instagram"] as? String, !instagram.isEmpty {
            self.instagramButton.isHidden = false
            self.socialMediaContainer.isHidden = false
        }
        if let snapchat = aa.properties["snapchat"] as? String, !snapchat.isEmpty {
            self.snapchatButton.isHidden = false
            self.socialMediaContainer.isHidden = false
        }
        if let twitter = aa.properties["twitter"] as? String, !twitter.isEmpty {
            self.twitterButton.isHidden = false
            self.socialMediaContainer.isHidden = false
        }

        self.view.layoutIfNeeded()
    }
}

protocol ChatCellDelegate: class {
    func chatCell(_ cell: ChatCell, didTapAccount account: MessageAccount)
    func chatCell(_ cell: ChatCell, didTapReplyFor account: MessageAccount)
}

class ChatCell: UITableViewCell {
    @IBOutlet weak var headerView: UIStackView!
    @IBOutlet weak var messageLabel: TagLabel!
    @IBOutlet weak var timestampLabel: UILabel!
    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var usernameLabel: UILabel!

    weak var delegate: ChatCellDelegate?
    var entry: ChatService.Channel.Entry?

    override func awakeFromNib() {
        super.awakeFromNib()
        self.headerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ChatCell.accountTapped)))
        self.userImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ChatCell.accountTapped)))
    }

    override func prepareForReuse() {
        self.userImageView.af_cancelImageRequest()
        self.userImageView.image = #imageLiteral(resourceName: "single")
        self.userImageView.isHidden = false
        self.headerView.isHidden = false
        self.timestampLabel.text = nil
        self.usernameLabel.text = nil
        self.messageLabel.text = nil
    }

    @objc private dynamic func accountTapped() {
        Logging.log("Chat Action", ["Action": "Account"])
        guard let account = self.entry?.account else {
            return
        }
        self.delegate?.chatCell(self, didTapAccount: account)
    }

    @IBAction func replyTapped(_ sender: Any) {
        Logging.log("Chat Action", ["Action": "Reply"])
        guard let account = self.entry?.account else {
            return
        }
        self.delegate?.chatCell(self, didTapReplyFor: account)
    }
}
