import FBSDKCoreKit
import FBSDKShareKit
import UIKit

class SuggestedUsersViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, SuggestedUserCellDelegate,
    FacebookInviteCellDelegate,
    FBSDKAppInviteDialogDelegate {

    @IBOutlet weak var friendsTable: UITableView!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.friendsTable.register(
            UINib(nibName: "SuggestedUserCell", bundle: nil),
            forCellReuseIdentifier: "SuggestedUserCell"
        )
        self.friendsTable.register(
            UINib(nibName: "FacebookInviteCell", bundle: nil),
            forCellReuseIdentifier: "FacebookInviteCell"
        )

        self.friendsTable.dataSource = self
        self.friendsTable.delegate = self

        let getFacebookFriends = Promise<Void>() { resolve, reject in
            guard let request = FBSDKGraphRequest(graphPath: "/me/friends", parameters: ["fields": "id,name,picture.type(normal){url}"]) else {
                resolve(())
                return
            }
            request.start { connection, result, error in
                resolve(())
                guard let data = (result as? DataType)?["data"] as? [DataType] else {
                    return
                }
                
                Logging.log("Find Facebook Friends", ["Result": data.count])
                
                self.friends = data.compactMap { user in
                    guard let identifier = user["id"] as? String,
                        let name = user["name"] as? String,
                        let thumbnail = ((user["picture"] as? DataType)?["data"] as? DataType)?["url"] as? String,
                        let url = URL(string: thumbnail)
                    else {
                            return nil
                    }
                    return User(id: "facebook:\(identifier)", username: nil, name: name, imageURL: url, type: "Facebook")
                }
                self.friendsTable.reloadData()
            }
        }
        let getTopUsers = Promise<Void>() { resolve, _ in
            Intent.getTopAccountsByVotes(tag: nil).perform(BackendClient.api) {
                resolve(())
                guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                    return
                }
                self.topUsers = data.prefix(15).compactMap {
                    guard let accountData = $0["account"] as? DataType else {
                        return nil
                    }
                    let account = AccountBase(data: accountData)
                    return User(
                        id: String(account.id),
                        username: account.username,
                        imageURL: account.imageURL,
                        type: "TopCreator",
                        isVerified: account.isVerified,
                        followerCount: account.followerCount)
                }
                self.friendsTable.reloadData()
            }
        }
        self.statusIndicatorView.showLoading()
        Promise.all([getFacebookFriends, getTopUsers]).then { _ in
            DispatchQueue.main.async {
                self.statusIndicatorView.hide()
            }
        }
        SettingsManager.didSuggestFriends = true
    }

    @IBAction func backTapped(_ sender: Any) {
        guard let navigation = self.navigationController else {
            let rootNavigation = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "RootNavigation")
            self.present(rootNavigation, animated: true)
            return
        }
        navigation.popViewController(animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return indexPath.section == 0 ? 75 : 70
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 0 // TODO: Re-enable Find Friends button
        case 1:
            return self.friends.count
        default:
            return self.topUsers.count
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "FacebookInviteCell", for: indexPath) as! FacebookInviteCell
            cell.delegate = self
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestedUserCell", for: indexPath) as! SuggestedUserCell
            cell.delegate = self
            cell.user = self.friends[indexPath.row]
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestedUserCell", for: indexPath) as! SuggestedUserCell
            cell.delegate = self
            cell.user = self.topUsers[indexPath.row]
            cell.popularLabel.isHidden = false
            return cell
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section != 0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0:
            return
        case 1:
            Logging.log("Suggested Users", ["Type": "Facebook",
                                            "Action": "Select"])
        default:
            Logging.log("Suggested Users", ["Type": "TopCreators",
                                            "Action": "Select"])
        }
        (tableView.cellForRow(at: indexPath) as? SuggestedUserCell)?.follow()
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 1:
            return self.friends.count > 0 ? 40 : 0.01
        case 2:
            return self.topUsers.count > 0 ? 40 : 0.01
        default:
            return 0.01
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return nil
        case 1:
            return self.friends.count > 0 ? "Facebook Friends" : nil
        default:
            return self.topUsers.count > 0 ? "You may be interested in" : nil
        }
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let view = view as? UITableViewHeaderFooterView else {
            return
        }
        view.contentView.backgroundColor = UIColor.uiBlack.withAlphaComponent(0.6)
        view.textLabel?.textColor = .white
    }

    // MARK: - SuggestedUserCellDelegate

    func suggestedUserCellFollow(_ user: User) {
        user.isFollowing = true
        guard let id = Int64(user.id) else {
            return
        }
        FollowService.instance.follow(ids: [id])
        Logging.log("Suggested Users", ["Type": user.type, "Action": "Follow"])
    }

    // MARK: - FacebookInviteCellDelegate

    func facebookInviteCellShowShare() {
        let dialog = FBSDKAppInviteDialog()
        guard dialog.canShow(), let session = BackendClient.api.session else {
            return
        }
        let content = FBSDKAppInviteContent()
        content.appLinkURL = URL(string: SettingsManager.getChannelURL(username: session.username))!
        if let url = session.imageURL {
            content.appInvitePreviewImageURL = url
        }
        dialog.fromViewController = self
        dialog.content = content
        dialog.delegate = self
        dialog.show()
        Logging.log("Suggested Users", ["Action": "FacebookInvite"])
    }

    // MARK: - FBSDKAppInviteDialogDelegate

    func appInviteDialog(_ appInviteDialog: FBSDKAppInviteDialog!, didFailWithError error: Error!) {
        Logging.danger("Facebook App Invite", ["Result": "Failed"])
    }

    func appInviteDialog(_ appInviteDialog: FBSDKAppInviteDialog!, didCompleteWithResults results: [AnyHashable : Any]!) {
        let cancelled = results?["completionGesture"] as? String == "cancel"
        Logging.log("Facebook App Invite", ["Result": cancelled ? "Cancel" : "Success"])
    }

    // MARK: - Private

    private var friends = [User]()
    private var topUsers = [User]()
    private var statusIndicatorView: StatusIndicatorView!
}

class User {
    let id: String
    let username: String?
    let name: String?
    let imageURL: URL?
    let type: String
    let isVerified: Bool
    let followerCount: Int?
    
    init(id: String, username: String?, name: String? = nil, imageURL: URL?, type: String, isVerified: Bool = false, followerCount: Int? = nil) {
        self.id = id
        self.username = username
        self.name = name
        self.imageURL = imageURL
        self.type = type
        self.isVerified = isVerified
        self.followerCount = followerCount
    }

    var isFollowing = false
}

protocol SuggestedUserCellDelegate {
    func suggestedUserCellFollow(_ user: User)
}

class SuggestedUserCell: SeparatorCell {
    var delegate: SuggestedUserCellDelegate?

    var user: User? {
        didSet {
            guard let friend = self.user else {
                self.profileImageView.af_cancelImageRequest()
                self.profileImageView.image = #imageLiteral(resourceName: "single")
                self.nameLabel.text = nil
                self.updateFollowButton(isFollowing: false)
                self.popularLabel.isHidden = true
                self.verifiedBadgeImageView.isHidden = true
                return
            }
            if let name = friend.name {
                self.nameLabel.text = name
            } else {
                self.nameLabel.text = "@\(friend.username ?? "")"
            }
            if let url = friend.imageURL {
                self.profileImageView.af_setImage(withURL: url)
            }
            if let followerCount = friend.followerCount {
                self.popularLabel.text = "\(followerCount.countLabelShort) subscribers"
                self.popularLabel.isHidden = false
            }
            self.updateFollowButton(isFollowing: friend.isFollowing)
            self.verifiedBadgeImageView.isHidden = !friend.isVerified
        }
    }

    @IBOutlet weak var followButton: LoaderButton!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var popularLabel: UILabel!
    @IBOutlet weak var verifiedBadgeImageView: UIImageView!

    
    override func prepareForReuse() {
        self.user = nil
    }

    @IBAction func followTapped(_ sender: Any) {
        self.follow()
    }
    
    func follow() {
        self.updateFollowButton(isFollowing: true)
        guard let friend = self.user else {
            return
        }
        if let followerCount = friend.followerCount {
            self.popularLabel.text = "\((followerCount + 1).countLabelShort) subscribers"
        }
        self.delegate?.suggestedUserCellFollow(friend)
    }

    func updateFollowButton(isFollowing: Bool) {
        if isFollowing {
            self.followButton.setTitleColor(.white, for: .normal)
            self.followButton.setTitle("check", for: .normal)
            self.followButton.isUserInteractionEnabled = false
        } else {
            self.followButton.setTitleColor(.uiYellow, for: .normal)
            self.followButton.setTitle("add", for: .normal)
            self.followButton.isUserInteractionEnabled = true
        }
    }
}

protocol FacebookInviteCellDelegate {
    func facebookInviteCellShowShare()
}

class FacebookInviteCell: UITableViewCell {
    var delegate: FacebookInviteCellDelegate?

    @IBAction func inviteTapped(_ sender: Any) {
        self.delegate?.facebookInviteCellShowShare()
    }
}
