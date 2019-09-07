import UIKit

class UserCell: SeparatorCell {
    @IBOutlet weak var followButton: LoaderButton!
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var sentBadgeLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var verifiedBadgeImageView: UIImageView!
    @IBOutlet weak var voteCountLabel: UILabel!
    @IBOutlet weak var rankLabel: UILabel!
    @IBOutlet weak var rankLabelWidth: NSLayoutConstraint!

    var user: Account? {
        didSet {
            if let name = self.user?.username {
                self.titleLabel.text = name
            }
            if let url = self.user?.imageURL {
                self.profileImageView.af_setImage(withURL: url)
            }
            if let verified = self.user?.isVerified {
                self.verifiedBadgeImageView.isHidden = !verified
            }
            if let user = self.user as? AccountWithFollowState, !user.isCurrentUser {
                self.updateFollowButton(state: user.isFollowing)
            } else {
                self.updateFollowButton(state: nil)
            }
        }
    }

    var rank: Int? {
        didSet {
            guard let rank = self.rank else {
                self.rankLabel.text = nil
                self.rankLabelWidth.constant = 0
                return
            }
            self.rankLabel.text = "\(rank)."
            self.rankLabelWidth.constant = 28
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.followButton.loader.activityIndicatorViewStyle = .white

        let highlightView = UIView()
        highlightView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        self.selectedBackgroundView = highlightView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.followButton.isLoading = false
        self.profileImageView.image = #imageLiteral(resourceName: "single")
        self.sentBadgeLabel.text = ""
        self.titleLabel.text = nil
        self.verifiedBadgeImageView.isHidden = true
        self.voteCountLabel.text = nil
    }

    // MARK: - Actions

    @IBAction func followButtonTapped(_ sender: LoaderButton) {
        guard let user = self.user as? AccountWithFollowState else {
            return
        }
        self.followButton.isLoading = true
        user.toggleFollowing {
            self.followButton.isLoading = false
            self.updateFollowButton(state: $0)
        }
    }

    // MARK: - Private

    private func updateFollowButton(state: Bool?) {
        guard let isFollowing = state else {
            self.followButton.setTitle("", for: .normal)
            self.followButton.isUserInteractionEnabled = false
            return
        }
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
