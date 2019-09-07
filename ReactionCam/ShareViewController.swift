import Alamofire
import AVFoundation
import FBSDKLoginKit
import FBSDKShareKit
import MessageUI
import Photos
import SafariServices
import TwitterKit
import TMTumblrSDK
import UIKit

class ShareViewController: UIViewController,
    ConversationImportDelegate,
    FBSDKAppInviteDialogDelegate,
    FBSDKSharingDelegate,
    MFMessageComposeViewControllerDelegate,
    SearchSectionDelegate,
    SFSafariViewControllerDelegate,
    UITableViewDataSource,
    UITableViewDelegate,
    UITextFieldDelegate
{
    enum Mode {
        case indeterminate
        case request(content: ContentInfo)
        case reshareOther(content: ContentInfo)
        case reshareOwn(content: ContentInfo)
    }

    var contentInfo: ContentInfo {
        switch self.mode {
        case .indeterminate:
            preconditionFailure("Cannot get content info in current ShareViewController mode")
        case let .request(content), let .reshareOther(content), let .reshareOwn(content):
            return content
        }
    }

    var mode: Mode = .indeterminate {
        didSet {
            guard case .indeterminate = oldValue else {
                assertionFailure("Only set ShareViewController mode once")
                return
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    var showFinish = true
    var source = "Unknown"

    // MARK: - Outlets

    @IBOutlet weak var autopostFacebookSwitch: UISwitch!
    @IBOutlet weak var autopostTwitterSwitch: UISwitch!
    @IBOutlet weak var autopostTumblrSwitch: UISwitch!
    @IBOutlet weak var autopostYouTubeSwitch: UISwitch!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var contentButton: UIButton!
    @IBOutlet weak var doneButton: UIButton!
    @IBOutlet weak var headerMetadataView: UIStackView!
    @IBOutlet weak var headerTitleLabel: UILabel!
    @IBOutlet weak var headerTitleView: UIView!
    @IBOutlet weak var headerTopSpaceConstraint: NSLayoutConstraint!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var instagramBadgeLabel: UILabel!
    @IBOutlet weak var itemAutopostFacebook: UIView!
    @IBOutlet weak var itemAutopostTumblr: UIView!
    @IBOutlet weak var itemAutopostTwitter: UIView!
    @IBOutlet weak var itemAutopostYouTube: UIView!
    @IBOutlet weak var itemInstagram: UIView!
    @IBOutlet weak var itemMessages: UIView!
    @IBOutlet weak var itemMore: UIView!
    @IBOutlet weak var itemSaveVideo: UIView!
    @IBOutlet weak var itemSearchUser: UIView!
    @IBOutlet weak var itemSnapchat: UIView!
    @IBOutlet weak var itemWhatsApp: UIView!
    @IBOutlet weak var itemYouTube: UIView!
    @IBOutlet weak var linkButton: UIButton!
    @IBOutlet weak var messagesBadgeLabel: UILabel!
    @IBOutlet weak var moreButtonLabel: UILabel!
    @IBOutlet weak var requestReactionsView: UIView!
    @IBOutlet weak var saveVideoBadgeLabel: UILabel!
    @IBOutlet weak var searchField: SearchTextField!
    @IBOutlet weak var searchUsersTable: UITableView!
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var snapchatBadgeLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var whatsAppBadgeLabel: UILabel!
    @IBOutlet weak var youTubeBadgeLabel: UILabel!

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.searchSection = SearchUserSection(delegate: self)
        Intent.getOwnFollowing(limit: nil, cursor: nil, idsOnly: false).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [[String: Any]] else {
                return
            }
            self.searchSection.subscriptions = data.compactMap(AccountBase.init(data:))
        }

        self.searchField.delegate = self
        self.searchUsersTable.delegate = self
        self.searchUsersTable.dataSource = self
        self.searchUsersTable.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)
        self.searchUsersTable.register(UINib(nibName: "UserCell", bundle: nil), forCellReuseIdentifier: "UserCell")
        self.searchUsersTable.register(UINib(nibName: "InviteCell", bundle: nil), forCellReuseIdentifier: "InviteCell")
        self.searchUsersTable.keyboardDismissMode = .onDrag

        self.updateSuggestedUsers()

        self.blackScreen.frame = self.view.bounds
        self.blackScreen.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        self.blackScreen.isHidden = true
        self.view.addSubview(self.blackScreen)
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.contentButton.imageView?.contentMode = .scaleAspectFill

        ContentService.instance.serviceConnected.addListener(self, method: ShareViewController.handleServiceConnected)

        // Make toggle rows tappable.
        self.itemAutopostFacebook.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ShareViewController.facebookAutopostTapped)))
        self.itemAutopostTumblr.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ShareViewController.tumblrAutopostTapped)))
        self.itemAutopostTwitter.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ShareViewController.twitterAutopostTapped)))
        self.itemAutopostYouTube.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ShareViewController.youTubeAutopostTapped)))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Logging.debug("Share Appeared", [
            "DiskSpace": FileManager.default.freeDiskSpace ?? -1,
            "Source": self.source])

        if case .indeterminate = self.mode {
            // Crash debug builds if mode has not been set.
            assertionFailure("ShareViewController presented without setting mode")
        }

        if let url = self.contentInfo.thumbnailURL {
            self.contentButton.af_setImageBiased(for: .normal, url: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
        }

        if let url = self.contentInfo.webURL?.absoluteString {
            self.linkButton.setTitle("🔗 \(url.replacingOccurrences(of: "https://www.reaction.cam", with: "rcam.at"))", for: .normal)
            self.linkButton.isHidden = false
        }

        self.doneButton.isHidden = !self.showFinish
        self.closeButton.isHidden = true
        self.requestReactionsView.isHidden = true
        self.itemSearchUser.isHidden = true
        self.itemAutopostFacebook.isHidden = true
        self.itemAutopostTwitter.isHidden = true
        self.itemAutopostTumblr.isHidden = true
        self.itemAutopostYouTube.isHidden = true
        self.itemInstagram.isHidden = true
        self.itemMessages.isHidden = true
        self.itemWhatsApp.isHidden = true
        self.itemMore.isHidden = true
        self.itemSnapchat.isHidden = true
        self.itemSaveVideo.isHidden = true

        switch self.mode {
        case .indeterminate:
            self.closeButton.isHidden = false
            self.itemSearchUser.isHidden = false
        case .request:
            self.requestReactionsView.isHidden = false
            self.titleLabel.text = "Request Reaction"
            self.headerTitleLabel.text = "Share with a friend to request a reaction. You'll get notified when they post it! 😝"
            self.closeButton.setTitle("keyboard_arrow_left", for: .normal)
            self.closeButton.isHidden = false
            self.itemSearchUser.isHidden = false
            self.searchUsersTable.isHidden = false
        case .reshareOther:
            self.titleLabel.text = "Share Video"
            self.headerTitleLabel.text = "PROTIP: Videos shared on multiple networks are 1.5x more likely to go viral! Pick a couple to share below. 🤑"
            self.itemSearchUser.isHidden = false
            self.itemInstagram.isHidden = !UIApplication.shared.canOpenURL(URL(string: "instagram://")!)
            self.itemSnapchat.isHidden = !UIApplication.shared.canOpenURL(URL(string: "snapchat://")!)
            self.itemMessages.isHidden = !MFMessageComposeViewController.canSendText()
            self.itemWhatsApp.isHidden = !UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!)
            self.itemMore.isHidden = false
            self.itemAutopostFacebook.isHidden = false
            self.itemAutopostTwitter.isHidden = false
        case .reshareOwn:
            self.titleLabel.text = "Share Video"
            self.headerTitleLabel.text = "PROTIP: The most successful vlogs start with friends and family. Share on your social media and ask them to reshare! 👫"
            self.itemSearchUser.isHidden = false
            self.itemInstagram.isHidden = !UIApplication.shared.canOpenURL(URL(string: "instagram://")!)
            self.itemSnapchat.isHidden = !UIApplication.shared.canOpenURL(URL(string: "snapchat://")!)
            self.itemMessages.isHidden = !MFMessageComposeViewController.canSendText()
            self.itemWhatsApp.isHidden = !UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!)
            self.itemMore.isHidden = false
            self.itemAutopostFacebook.isHidden = false
            self.itemAutopostTwitter.isHidden = false
            self.itemAutopostYouTube.isHidden = false
            self.itemSaveVideo.isHidden = false
        }

        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    // MARK: - ConversationImportDelegate

    var conversationImportAnchorView: UIView {
        return self.searchField
    }

    // MARK: - FBSDKAppInviteDialogDelegate

    func appInviteDialog(_ appInviteDialog: FBSDKAppInviteDialog!, didFailWithError error: Error!) {
        Logging.danger("Facebook App Invite", ["Result": "Failed", "Error": error.localizedDescription])
    }

    func appInviteDialog(_ appInviteDialog: FBSDKAppInviteDialog!, didCompleteWithResults results: [AnyHashable : Any]!) {
        let cancelled = results?["completionGesture"] as? String == "cancel"
        Logging.log("Facebook App Invite", ["Result": cancelled ? "Cancel" : "Success"])
    }

    // MARK: - FBSDKSharingDelegate

    func sharer(_ sharer: FBSDKSharing!, didCompleteWithResults results: [AnyHashable : Any]!) {
        Logging.log("Facebook Share Action", ["Result": "Success"])
    }

    func sharer(_ sharer: FBSDKSharing!, didFailWithError error: Error!) {
        Logging.log("Facebook Share Action", ["Result": "Failed"])
    }

    func sharerDidCancel(_ sharer: FBSDKSharing!) {
        Logging.log("Facebook Share Action", ["Result": "Cancelled"])
    }

    // MARK: - MFMessageComposeViewControllerDelegate

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }

    // MARK: - SearchSectionDelegate

    func searchSection(_ section: TableViewSection, didSelectAccount account: Account) {
        // TODO: This is madness. See didSelectRowAt instead for the logic you were looking for.
    }

    func searchSection(_ section: TableViewSection, didSelectContentResult content: ContentResult) {
    }

    func searchSectionNeedsReload(_ section: TableViewSection) {
        self.searchUsersTable.reloadData()
    }

    func searchSection(_ section: TableViewSection, shouldShowAccount account: Account) -> Bool {
        return true
    }

    // MARK: - SFSafariViewControllerDelegate

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        self.autopostYouTubeSwitch.isEnabled = true
        self.autopostYouTubeSwitch.isOn = false
        self.webController = nil
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case Section.searchResults, Section.invite:
            return 0
        case Section.topReactors:
            return (self.searchField.text?.isEmpty ?? true) && !self.suggestedAccountAndScore.isEmpty ? 50 : 0
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case Section.searchResults:
            return self.searchSection.count
        case Section.invite:
            return 1
        case Section.topReactors:
            return self.searchField.text?.isEmpty ?? true ? self.suggestedAccountAndScore.count : 0
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case Section.searchResults:
            return self.searchSection.rowHeight
        case Section.invite:
            return 100
        case Section.topReactors:
            return 65
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header: String
        switch section {
        case Section.searchResults:
            if let title = self.searchSection.headerTitle {
                header = title
            } else {
                return nil
            }
        case Section.topReactors:
            header = "TOP REACTORS"
        default:
            return nil
        }

        let headerView = UIView()
        headerView.frame = CGRect(x: 0, y: 0, width: tableView.frame.width, height: 50)
        headerView.backgroundColor = UIColor.uiBlack.withAlphaComponent(0.95)
        let textLabel = UILabel(frame: headerView.bounds.offsetBy(dx: 18, dy: 0))
        textLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        textLabel.textColor = .white
        textLabel.text = header
        headerView.addSubview(textLabel)
        return headerView
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case Section.searchResults:
            let cell = tableView.dequeueReusableCell(withIdentifier: self.searchSection.cellReuseIdentifier, for: indexPath) as! UserCell
            self.searchSection.populateCell(indexPath.row, cell: cell)
            if let user = cell.user {
                cell.sentBadgeLabel.isHidden = false
                cell.sentBadgeLabel.alpha = 1
                cell.sentBadgeLabel.text = self.userBadges[user.id]
            }
            return cell
        case Section.invite:
            return tableView.dequeueReusableCell(withIdentifier: "InviteCell", for: indexPath)
        case Section.topReactors:
            let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath) as! UserCell
            let accountAndScore = self.suggestedAccountAndScore[indexPath.row]
            cell.user = accountAndScore.0
            cell.voteCountLabel.text = "\(accountAndScore.1) 👍"
            if let user = cell.user {
                cell.sentBadgeLabel.isHidden = false
                cell.sentBadgeLabel.alpha = 1
                cell.sentBadgeLabel.text = self.userBadges[user.id]
            }
            return cell
        default:
            assertionFailure("Unhandled section")
            return UITableViewCell()
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch indexPath.section {
        case Section.invite:
            return false
        default:
            return true
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case Section.searchResults, Section.topReactors:
            let cell = tableView.cellForRow(at: indexPath) as! UserCell
            guard let user = cell.user, !self.userBadges.keys.contains(user.id) else {
                return
            }
            Logging.log(self.logType, [
                "Username": user.username,
                "UserType": indexPath.section == 0 ? "SearchResult" : "Suggested"])
            self.sendContentRequest(to: user.username)
            if indexPath.section == Section.searchResults {
                // Calling this ensures the appropriate logging is made.
                let _ = self.searchSection.handleSelect(indexPath.row)
            }
            if let badgeLabel = cell.sentBadgeLabel {
                self.showBadge(badgeLabel: badgeLabel)
                self.userBadges[user.id] = badgeLabel.text
            }
        default:
            break
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.searchView.showAnimated()
        self.searchUsersTable.showAnimated()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    // MARK: - Actions

    @IBAction func closeSearchTapped(_ sender: Any) {
        self.searchView.hideAnimated()
        self.searchField.text = ""
        self.searchField.resignFirstResponder()
        self.searchUsersTable.reloadData()

        switch self.mode {
        case .indeterminate, .reshareOther, .reshareOwn:
            self.searchUsersTable.hideAnimated()
        default:
            break
        }

        UIView.animate(withDuration: 0.2) {
            self.headerTopSpaceConstraint.constant = 0
            self.view.layoutIfNeeded()
            self.headerMetadataView.alpha = 1
            self.headerTitleView.alpha = 1
        }
    }

    @IBAction func closeTapped(_ sender: Any) {
        Logging.debug("\(self.logType) Action", ["Action": "Back"])
        self.cleanUp()
        self.navigationController?.popViewController(animated: true)
    }

    @IBAction func doneTapped(_ sender: Any) {
        Logging.debug("\(self.logType) Action", ["Action": "Done"])
        self.cleanUp()
        switch self.mode {
        case .request:
            self.navigationController?.popToRootViewControllerModal()
        case let .reshareOther(content), let .reshareOwn(content):
            if self.autopostYouTubeSwitch.isOn {
                ContentService.instance.uploadToYouTube(id: content.id)
            }
            if self.autopostFacebookSwitch.isOn {
                ContentService.instance.postToFacebook(content: content)
            }
            if self.autopostTwitterSwitch.isOn {
                ContentService.instance.postToTwitter(content: content)
            }
            if self.autopostTumblrSwitch.isOn {
                ContentService.instance.postToTumblr(content: content)
            }
            self.navigationController?.popViewControllerModal()
        default:
            self.navigationController?.popViewControllerModal()
        }
        AppDelegate.notifyIfSquelched()
    }

    @IBAction func linkButtonTapped(_ sender: UIButton) {
        Logging.debug("\(self.logType) Action", [
            "Action": "Copy Link"])
        guard let url = self.contentInfo.webURL?.absoluteString else {
            return
        }
        UIPasteboard.general.string = url
        self.statusIndicatorView.showConfirmation(title: "Link Copied")
    }

    @IBAction func openLinkTapped(_ sender: UIButton) {
        Logging.debug("\(self.logType) Action", ["Action": "Open Link"])
        if let url = self.contentInfo.webURL {
            UIApplication.shared.open(url, options: [:])
        }
    }

    @IBAction func searchButtonTapped(_ sender: Any) {
        self.searchView.showAnimated()
        self.searchUsersTable.showAnimated()
        self.searchField.becomeFirstResponder()
        UIView.animate(withDuration: 0.2) {
            // Start with the value that would hide the entire header.
            var dy = -self.headerView.frame.height
            if #available(iOS 11.0, *) {
                // Make room for the safe area.
                dy += self.view.safeAreaInsets.top
            }
            // Make room for the search view.
            dy += self.searchView.frame.height
            self.headerTopSpaceConstraint.constant = dy
            self.view.layoutIfNeeded()
            // Also fade out the header elements.
            self.headerMetadataView.alpha = 0
            self.headerTitleView.alpha = 0
        }
    }

    @IBAction func searchFieldEditingChanged(_ sender: Any) {
        // Reset search cell
        guard let text = self.searchField.text?.trimmingCharacters(in: .whitespaces) else {
            return
        }
        self.searchField.reloadInputViews()
        self.searchSection.search(text)
    }

    // MARK: - Actions (Autoposting)

    @IBAction func facebookAutopostToggled(_ sender: UISwitch) {
        guard sender.isOn else {
            Logging.log("Facebook Autopost Toggle", ["Result": "Off"])
            return
        }

        let permission = "publish_actions"
        guard !(FBSDKAccessToken.current()?.permissions?.contains(permission) ?? false) else {
            SettingsManager.autopostFacebook = true
            return
        }
        self.statusIndicatorView.showLoading()
        AppDelegate.connectFacebook(presenter: self) { success in
            let login = FBSDKLoginManager()
            login.logIn(withPublishPermissions: [permission], from: self) { session, error in
                self.statusIndicatorView.hide()
                let success = session?.grantedPermissions?.contains(permission) ?? false
                self.autopostFacebookSwitch.isOn = success
                Logging.log("Facebook Autopost Toggle", ["Result": success])
            }
        }
    }

    @IBAction func tumblrAutopostToggled(_ sender: UISwitch) {
        guard sender.isOn else {
            Logging.debug("Tumblr Autopost Toggle", ["Result": "Off"])
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

    @IBAction func twitterAutopostToggled(_ sender: UISwitch) {
        guard sender.isOn else {
            Logging.debug("Twitter Autopost Toggle", ["Result": "Off"])
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

    @IBAction func youTubeAutopostToggled(_ sender: UISwitch) {
        guard sender.isOn else {
            Logging.debug("YouTube Autopost Toggle", ["Result": "Off"])
            return
        }
        let enable: () -> () = {
            guard let session = BackendClient.api.session else {
                return
            }
            guard session.hasService(id: "youtube") else {
                self.autopostYouTubeSwitch.isEnabled = false
                let vc = SFSafariViewController(url: SettingsManager.youTubeAuthURL)
                self.webController = vc
                vc.delegate = self
                self.present(vc, animated: true)
                return
            }
            Logging.debug("YouTube Autopost Toggle", ["Result": "On"])
            SettingsManager.autopostYouTube = true
        }
        if self.contentInfo.created.daysAgo < 1 {
            let alert = UIAlertController(
                title: "Duplicate Warning",
                message: "Videos may take a while to show up on your YouTube channel. Are you sure you want to proceed?",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Share", style: .default) { _ in
                enable()
            })
            alert.addCancel(title: "Cancel") {
                self.autopostYouTubeSwitch.setOn(false, animated: true)
            }
            self.present(alert, animated: true)
        } else {
            enable()
        }
    }

    // MARK: - Actions (InviteCell)

    @IBAction func facebookInviteTapped(_ sender: UIButton) {
        Logging.info("Request Reaction Action", ["Action": "Facebook"])
        guard let session = BackendClient.api.session else {
            return
        }
        guard let url = self.contentInfo.webURL?.absoluteString else {
            // TODO: Show error.
            Logging.danger("\(self.logType) Error", [
                "Destination": "Request Reaction Facebook",
                "Error": "MissingWebURL"])
            return
        }
        let messengerDialog = FBSDKMessageDialog()
        if messengerDialog.canShow() {
            let linkContent = FBSDKShareLinkContent()
            linkContent.contentURL = URL(string: url)
            messengerDialog.shareContent = linkContent
            messengerDialog.shouldFailOnDataError = true
            messengerDialog.show()
            Logging.log("Request Reaction Result", ["Result": "Share to Messenger"])
        } else {
            let facebookDialog = FBSDKAppInviteDialog()
            if facebookDialog.canShow() {
                let content = FBSDKAppInviteContent()
                content.appLinkURL = URL(string: url)!
                // TODO make this a link to the content thumb, not the profile
                if let imageUrl = session.imageURL {
                    content.appInvitePreviewImageURL = imageUrl
                }
                facebookDialog.fromViewController = self
                facebookDialog.content = content
                facebookDialog.delegate = self
                facebookDialog.show()
                Logging.log("Request Reaction Result", ["Result": "Share to Facebook"])
            }
        }
    }

    @IBAction func shareLinkTapped(_ sender: UIButton) {
        Logging.log("Request Reaction Action", ["Action": "Send Link"])
        self.showShareLink(destination: "Request Reaction Send Link", sourceView: sender)
    }

    // MARK: - Actions (Share destinations)

    @IBAction func instagramTapped(_ sender: UIButton) {
        Logging.debug("\(self.logType) Action", [
            "Action": "Pick Destination",
            "Destination": "Instagram"])
        self.shareToInstagram(sender: sender)
        self.showBadge(badgeLabel: self.instagramBadgeLabel)
    }

    @IBAction func messagesTapped(_ sender: UIButton) {
        Logging.debug("\(self.logType) Action", [
            "Action": "Pick Destination",
            "Destination": "Messages"])
        guard MFMessageComposeViewController.canSendText() else {
            self.showInstallAlert(appName: "Messages")
            return
        }
        guard let copy = self.generateShareCopy() else {
            // TODO: Show error.
            Logging.danger("\(self.logType) Error", [
                "Destination": "Messages",
                "Error": "MissingWebURL"])
            return
        }
        let vc = MFMessageComposeViewController()
        vc.body = copy
        vc.messageComposeDelegate = self
        self.present(vc, animated: true)
        self.showBadge(badgeLabel: self.messagesBadgeLabel)
        Logging.info("\(self.logType) Success", [
            "Destination": "Messages",
            "Duration": self.contentInfo.duration])
    }

    @IBAction func moreTapped(_ sender: UIButton) {
        switch self.mode {
        case .indeterminate, .request:
            break
        case .reshareOther, .reshareOwn:
            self.showShareLink(destination: "Share Link", sourceView: self.moreButtonLabel)
        }
    }

    @IBAction func saveVideoTapped(_ sender: UIButton) {
        self.showShareVideo(destination: "Save Video", sourceView: sender)
    }

    @IBAction func snapchatTapped(_ sender: UIButton) {
        Logging.debug("\(self.logType) Action", [
            "Action": "Pick Destination",
            "Destination": "Snapchat"])
        self.shareToSnapchat(sender: sender)
        self.showBadge(badgeLabel: self.snapchatBadgeLabel)
    }

    @IBAction func whatsAppTapped(_ sender: UIButton) {
        Logging.debug("\(self.logType) Action", [
            "Action": "Pick Destination",
            "Destination": "WhatsApp"])
        let appURL = URL(string: "whatsapp://")!
        guard UIApplication.shared.canOpenURL(appURL) else {
            self.showInstallAlert(appName: "WhatsApp")
            return
        }
        guard
            let copy = self.generateShareCopy(),
            let escapedCopy = copy.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else
        {
            // TODO: Show error.
            Logging.danger("\(self.logType) Error", [
                "Destination": "WhatsApp",
                "Error": "MissingWebURL"])
            return
        }
        let deepAppURL = URL(string: "whatsapp://send?text=\(escapedCopy)")!
        UIApplication.shared.open(deepAppURL, options: [:], completionHandler: nil)
        self.showBadge(badgeLabel: self.whatsAppBadgeLabel)
        Logging.info("\(self.logType) Success", [
            "Destination": "WhatsApp",
            "Duration": self.contentInfo.duration])
    }

    // MARK: - Gesture recognizers

    @objc private dynamic func facebookAutopostTapped() {
        guard autopostFacebookSwitch.isEnabled else {
            return
        }
        self.autopostFacebookSwitch.setOn(!self.autopostFacebookSwitch.isOn, animated: true)
        self.facebookAutopostToggled(self.autopostFacebookSwitch)
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

    // MARK: - Private

    private struct Section {
        static let invite = 0
        static let searchResults = 1
        static let topReactors = 2
    }

    private let blackScreen = UIView()

    private var asset: AVURLAsset?
    private var savedAssets = [(AVURLAsset, String?)]()
    private var importAlert: ConversationImportAlert?
    private var requestsSent = 0
    private var userBadges = [Int64: String]()
    private var webController: SFSafariViewController?

    private var logType: String {
        switch self.mode {
        case .indeterminate:
            return "Share (Indeterminate)"
        case .request:
            return "Share (Request)"
        case .reshareOther:
            return "Share (Other)"
        case .reshareOwn:
            return "Share (Own)"
        }
    }

    private var searchSection: SearchUserSection!
    private var statusIndicatorView: StatusIndicatorView!

    private var suggestedAccountAndScore = [(Account, Int)]() {
        didSet {
            self.searchUsersTable.reloadData()
        }
    }

    private func cacheVideo(callback: @escaping (AVURLAsset) -> ()) {
        let remoteURL: URL
        if let asset = self.asset {
            remoteURL = asset.url
            guard !remoteURL.isFileURL else {
                callback(asset)
                return
            }
        } else if case let .reshareOther(content) = self.mode, let url = content.videoURL {
            remoteURL = url
        } else if case let .reshareOwn(content) = self.mode, let url = content.videoURL {
            remoteURL = url
        } else {
            assertionFailure("Cannot cache video in current ShareViewController mode")
            NSLog("%@", "WARNING: Attempted to cache video but there's no video URL")
            return
        }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MediaCache")
        let localURL = caches.appendingPathComponent(remoteURL.lastPathComponent).appendingPathExtension("mp4")
        let request = Alamofire.download(remoteURL, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil, to: {
            (_, _) -> (URL, DownloadRequest.DownloadOptions) in
            // Return the path on disk where the file should be stored.
            return (localURL, [])
        })
        self.statusIndicatorView.showLoading(title: "Loading 0%")
        UIApplication.shared.isIdleTimerDisabled = true
        self.blackScreen.showAnimated()
        request.downloadProgress() { progress in
            DispatchQueue.main.async {
                self.statusIndicatorView.showLoading(title: "Loading \(Int(progress.fractionCompleted * 100))%")
            }
        }
        request.response() {
            self.blackScreen.hideAnimated()
            self.statusIndicatorView.hide()
            UIApplication.shared.isIdleTimerDisabled = false
            if let error = $0.error, (error as NSError).code != NSFileWriteFileExistsError {
                NSLog("Warning: Could not cache video \(error)")
                Logging.warning("\(self.logType) Error", [
                    "Error": error.localizedDescription])
                let alert = UIAlertController(title: "Oops!", message: "Download failed. Please try again later.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            let asset = AVURLAsset(url: localURL)
            self.asset = asset
            callback(asset)
        }
    }

    private func fetchLatestAsset() -> PHAsset? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        return PHAsset.fetchAssets(with: .video, options: fetchOptions).firstObject
    }

    private func cleanUp() {
        // Clean up any cached assets
        guard let asset = self.asset, FileManager.default.fileExists(atPath: asset.url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: asset.url)
        } catch {
            Logging.warning("\(self.logType) Error", ["Error": error.localizedDescription])
        }
    }

    private func generateInstagramCaption() -> String? {
        if let title = self.contentInfo.title {
            return title + " on @reaction.cam"
        } else {
            return "on @reaction.cam"
        }
    }
    
    private func generateShareCopy() -> String? {
        guard let url = self.contentInfo.webURL?.absoluteString else {
            return nil
        }
        if let title = self.contentInfo.title {
            return title + " " + url
        } else {
            return url
        }
    }

    private func handleServiceConnected(service: String, code: Int) {
        self.webController?.dismiss(animated: true) {
            self.webController = nil
        }
        switch service {
        case "youtube":
            self.autopostYouTubeSwitch.isEnabled = true
            self.autopostYouTubeSwitch.isOn = code == 200
            SettingsManager.autopostYouTube = code == 200
            if code == 409 {
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
            }
        default:
            break
        }
    }

    private func makeTeaser(asset: AVURLAsset, maxDuration: TimeInterval = 15, completion: @escaping (AVURLAsset) -> ()) {
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

    private func makeVideoPortrait(asset: AVURLAsset, completion: @escaping (AVURLAsset?) -> ()) {
        // Must be run on main thread!
        guard let fileSize = asset.url.fileSize else {
            completion(nil)
            return
        }

        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
            guard
                let sourceVideoTrack = asset.tracks(withMediaType: .video).first,
                let sourceAudioTrack = asset.tracks(withMediaType: .audio).first
                else
            {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let size = sourceVideoTrack.naturalSize
            guard size.width > size.height else {
                // No rotation necessary.
                DispatchQueue.main.async { completion(asset) }
                return
            }

            let range = CMTimeRange(start: kCMTimeZero, duration: asset.duration)

            let composition = AVMutableComposition()
            guard
                let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                else
            {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                try video.insertTimeRange(range, of: sourceVideoTrack, at: kCMTimeZero)
                try audio.insertTimeRange(range, of: sourceAudioTrack, at: kCMTimeZero)
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let rotate = CGAffineTransform(translationX: size.height, y: 0).rotated(by: .pi / 2)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
            layerInstruction.setTransform(rotate, at: kCMTimeZero)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            instruction.layerInstructions = [layerInstruction]

            let videoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = sourceVideoTrack.minFrameDuration
            videoComposition.instructions = [instruction]
            videoComposition.renderSize = CGSize(width: size.height, height: size.width)

            let preset = (max(size.width, size.height) >= 1920 ? AVAssetExportPreset1920x1080 : AVAssetExportPreset1280x720)
            guard let export = AVAssetExportSession(asset: composition, presetName: preset) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let url = URL.temporaryFileURL("mp4")
            export.canPerformMultiplePassesOverSourceMediaData = true
            export.fileLengthLimit = fileSize
            export.outputFileType = .mp4
            export.outputURL = url
            export.shouldOptimizeForNetworkUse = true
            export.timeRange = range
            export.videoComposition = videoComposition

            var timer: Timer?
            DispatchQueue.main.async {
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    self.statusIndicatorView.showLoading(title: "Exporting \(Int(export.progress * 100))%")
                }
            }
            export.exportAsynchronously {
                timer?.invalidate()
                guard export.status == .completed else {
                    NSLog("WARNING: Failed to export video (\(export.error?.localizedDescription ?? "unknown error"))")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                DispatchQueue.main.async { completion(AVURLAsset(url: url)) }
            }
        }
    }

    private func makeVideoSquare(asset: AVURLAsset, completion: @escaping (AVURLAsset?) -> ()) {
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
            guard
                let sourceVideoTrack = asset.tracks(withMediaType: .video).first,
                let sourceAudioTrack = asset.tracks(withMediaType: .audio).first
                else
            {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let size = sourceVideoTrack.naturalSize
            guard size.width != size.height else {
                // No change necessary.
                DispatchQueue.main.async { completion(asset) }
                return
            }

            let long = max(size.width, size.height)
            let range = CMTimeRange(start: kCMTimeZero, duration: asset.duration)

            let composition = AVMutableComposition()
            guard
                let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                else
            {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                try video.insertTimeRange(range, of: sourceVideoTrack, at: kCMTimeZero)
                try audio.insertTimeRange(range, of: sourceAudioTrack, at: kCMTimeZero)
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            var t = sourceVideoTrack.preferredTransform
            let divisor: CGFloat
            switch (t.a, t.b, t.c, t.d) {
            case (0, 1, -1, 0), (0, -1, 1, 0):
                divisor = -2
            default:
                divisor = 2
            }
            t = t.translatedBy(x: (long - size.width) / divisor, y: (long - size.height) / divisor)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack:video)
            layerInstruction.setTransform(t, at: kCMTimeZero)

            let instruction = AVMutableVideoCompositionInstruction()
            let white = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 1, 1, 1])
            instruction.backgroundColor = white
            instruction.timeRange = range
            instruction.layerInstructions = [layerInstruction]

            let videoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = sourceVideoTrack.minFrameDuration
            videoComposition.instructions = [instruction]
            videoComposition.renderSize = CGSize(width: long, height: long)

            let preset = (long >= 1920 ? AVAssetExportPreset1920x1080 : AVAssetExportPreset1280x720)
            guard let export = AVAssetExportSession(asset: composition, presetName: preset) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let url = URL.temporaryFileURL("mp4")
            export.outputFileType = .mp4
            export.outputURL = url
            export.timeRange = range
            export.videoComposition = videoComposition

            var timer: Timer?
            DispatchQueue.main.async {
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    self.statusIndicatorView.showLoading(title: "Exporting \(Int(export.progress * 100))%")
                }
            }
            export.exportAsynchronously {
                timer?.invalidate()
                guard export.status == .completed else {
                    NSLog("WARNING: Failed to export video (\(export.error?.localizedDescription ?? "unknown error"))")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                DispatchQueue.main.async { completion(AVURLAsset(url: url)) }
            }
        }
    }

    private func save(source: String, completion: @escaping (String?, AVURLAsset) -> Void) {
        self.cacheVideo() { asset in
            self.save(asset, source: source) {
                completion($0, asset)
            }
        }
    }

    private func save(_ asset: AVURLAsset, source: String, completion: @escaping (String?) -> Void) {
        // Must run on main thread!
        guard asset.url.isFileURL else {
            completion(nil)
            return
        }
        if let localId = self.savedAssets.first(where: { $0.0 == asset })?.1 {
            completion(localId)
        } else {
            self.statusIndicatorView.showLoading()
            MediaManager.save(asset: asset, source: source) {
                self.statusIndicatorView.hide()
                if $0 != nil {
                    self.savedAssets.append((asset, $0))
                }
                completion($0)
            }
        }
    }

    private func sendContentRequest(to username: String) {
        let requestType = self.searchField.hasText ? "Search" : "Suggested"
        Intent.createContentRequest(identifier: username, relatedContent: self.contentInfo.ref).perform(BackendClient.api) {
            if $0.successful {
                Logging.info("\(self.logType) Success", [
                    "Destination": "Request Reaction",
                    "Username": username,
                    "UserType": requestType])
                return
            }
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
            alert.addCancel(title: "Try Again")
            if $0.code == 404 {
                Logging.warning("\(self.logType) Error", ["Error": "NotFound"])
                alert.title = "Can't find @\(username)"
                alert.message = "Are you sure that's the right username?"
            } else {
                Logging.danger("\(self.logType) Error", ["Error": "Unknown\($0.code)"])
                alert.title = "Uh-oh!"
                alert.message = "Something went wrong when sending the request. Double check your connection."
            }
            self.present(alert, animated: true)
        }
        self.searchField.clearClicked()
        self.requestsSent += 1
        if self.requestsSent >= 10 {
            let alert = UIAlertController(title: "Did you know?", message: "You can promote your content and get reactions if you become a verified artist!", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Learn More", style: .default) { _ in
                UIApplication.shared.open(SettingsManager.helpPromoteURL)
            })
            alert.addCancel(title: "Later")
            self.present(alert, animated: true)
        }
    }

    private func shareToInstagram(sender: UIView) {
        guard UIApplication.shared.canOpenURL(URL(string: "instagram://app")!) else {
            self.showInstallAlert(appName: "Instagram")
            return
        }

        self.cacheVideo() { asset in
            self.makeTeaser(asset: asset) { asset in
                self.view.isUserInteractionEnabled = false
                // TODO: Remove hack once we have promise pattern.
                // This is necessary for now as the hideAnimated call within cacheVideo() for the status indicator may not have completed.
                self.view.isUserInteractionEnabled = true
                self.statusIndicatorView.hide()
                self.save(asset, source: "Share Instagram") { localId in
                    guard let id = localId else {
                        Logging.danger("\(self.logType) Error", ["Error": "SaveFailed"])
                        return
                    }
                    UIPasteboard.general.string = self.generateInstagramCaption()
                    let alert = UIAlertController(title: "Paste your caption and tag @reaction.cam 🔖", message: nil, preferredStyle: .alert)
                    let appURL = URL(string: "instagram://library?LocalIdentifier=\(id)")!
                    alert.addAction(UIAlertAction(title: "Got it 🙏", style: .cancel) { _ in
                        UIApplication.shared.open(appURL, options: [:], completionHandler: nil)
                        Logging.info("\(self.logType) Success", [
                            "Destination": "Instagram",
                            "Duration": asset.duration.seconds])
                    })
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func shareToSnapchat(sender: UIView) {
        let appURL = URL(string: "snapchat://")!
        guard UIApplication.shared.canOpenURL(appURL) else {
            self.showInstallAlert(appName: "Snapchat")
            return
        }

        self.cacheVideo { asset in
            self.makeTeaser(asset: asset, maxDuration: 10) { asset in
                self.save(asset, source: "Share Snapchat") { localId in
                    guard localId != nil else {
                        Logging.danger("\(self.logType) Error", ["Error": "SaveFailed"])
                        return
                    }
                    guard let url = self.contentInfo.webURL?.absoluteString else {
                        // TODO: Show error.
                        Logging.danger("\(self.logType) Error", [
                            "Destination": "Snapchat",
                            "Error": "MissingWebURL"])
                        return
                    }
                    UIPasteboard.general.string = url

                    let alert = UIAlertController(title: "Snap Saved", message: "\nStep 1: pick the snap from Camera Roll in Memories\n\n Step 2: Tap \"Send\" and paste the link to the full video", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Open Snapchat", style: .cancel) { _ in
                        UIApplication.shared.open(appURL, options: [:], completionHandler: nil)
                    })
                    self.present(alert, animated: true)
                    Logging.info("\(self.logType) Success", [
                        "Destination": "Snapchat",
                        "Duration": asset.duration.seconds])
                }
            }
        }
    }

    private func showBadge(badgeLabel: UILabel) {
        badgeLabel.alpha = 0
        badgeLabel.isHidden = false
        UIView.animate(withDuration: 0.3) {
            badgeLabel.text = SettingsManager.shareBadges[Int(arc4random_uniform(UInt32(SettingsManager.shareBadges.count)))]
            badgeLabel.alpha = 1
        }
    }

    private func showInstallAlert(appName: String) {
        let alert = UIAlertController(title: "\(appName) is not installed", message: "Please download it and try again.", preferredStyle: .alert)
        var url : String
        switch appName {
        case "Facebook": url = "itms-apps://itunes.apple.com/us/app/facebook/id284882215?mt=8"
        case "Instagram": url = "itms-apps://itunes.apple.com/us/app/instagram/id389801252?mt=8"
        case "musical.ly": url = "itms-apps://itunes.apple.com/us/app/musical-ly-your-video-social-network/id835599320?mt=8"
        case "Snapchat": url = "itms-apps://itunes.apple.com/us/app/snapchat/id447188370?mt=8"
        case "Twitter": url = "itms-apps://itunes.apple.com/us/app/twitter/id333903271?mt=8"
        default: url = ""
        }
        if !url.isEmpty {
            alert.addAction(UIAlertAction(title: "Install \(appName) 📲", style: .cancel) { _ in
                UIApplication.shared.open(URL(string: url)!, options: [:], completionHandler: nil)
            })
        } else {
            alert.addCancel(title: "Got it")
        }
        self.present(alert, animated: true)
        Logging.warning("Share Install Alert", ["AppName": appName])
    }

    private func showShareLink(destination: String, sourceView: UIView) {
        Logging.debug("\(self.logType) Action", [
            "Action": "Pick Destination",
            "Destination": destination])
        guard let copy = self.generateShareCopy() else {
            // TODO: Show error.
            Logging.danger("\(self.logType) Error", [
                "Destination": destination,
                "Error": "MissingWebURL"])
            return
        }
        let share = UIActivityViewController(activityItems: [DynamicActivityItem(copy)], applicationActivities: nil)
        share.completionWithItemsHandler = { activity, success, _, error in
            guard success else {
                if let error = error {
                    Logging.warning("\(self.logType) Error", [
                        "Description": error.localizedDescription,
                        "Destination": "\(activity?.rawValue ?? "Other") (Link)"])
                } else {
                    Logging.debug("\(self.logType) Action", [
                        "Action": "Cancel",
                        "Destination": "\(activity?.rawValue ?? "Other") (Link)"])
                }
                return
            }
            Logging.info("\(self.logType) Success", [
                "Destination": "\(activity?.rawValue ?? "Other") (Link)",
                "Duration": self.contentInfo.duration])
        }
        share.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
        share.configurePopover(sourceView: sourceView)
        self.present(share, animated: true)
    }

    private func showShareVideo(destination: String, sourceView: UIView) {
        Logging.debug("\(self.logType) Action", [
            "Action": "Pick Destination",
            "Destination": destination])
        self.cacheVideo() { asset in
            // TODO: Bring back credit alert?
            let share = UIActivityViewController(activityItems: [asset.url], applicationActivities: nil)
            share.completionWithItemsHandler = { activity, success, _, error in
                guard success else {
                    if let error = error {
                        Logging.warning("\(self.logType) Error", [
                            "Description": error.localizedDescription,
                            "Destination": "\(activity?.rawValue ?? "Other") (Video)"])
                    } else {
                        Logging.debug("\(self.logType) Action", [
                            "Action": "Cancel",
                            "Destination": "\(activity?.rawValue ?? "Other") (Video)"])
                    }
                    return
                }
                Logging.info("\(self.logType) Success", [
                    "Destination": "\(activity?.rawValue ?? "Other") (Video)",
                    "Duration": asset.duration.seconds])
            }
            share.excludedActivityTypes = SettingsManager.shareFileExcludedActivityTypes
            share.configurePopover(sourceView: sourceView)
            self.present(share, animated: true)
        }
    }

    private func updateSuggestedUsers() {
        Intent.getTopAccountsByVotes(tag: nil).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                return
            }
            self.suggestedAccountAndScore = data.compactMap {
                guard let account = $0["account"] as? DataType, let score = $0["score"] as? Int else {
                    return nil
                }
                return (AccountBase(data: account), score)
            }
        }
    }
}
