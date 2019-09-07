import UIKit

class ContentPreviewCell: SeparatorCell {
    @IBOutlet weak var fireCountLabel: UILabel!
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var featuredLabel: UILabel!
    @IBOutlet weak var repostLabel: UIView!
    @IBOutlet weak var reactionCountLabel: UILabel!
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var verifiedBadgeImage: UIImageView!
    @IBOutlet weak var viewsContainerView: UIView!
    @IBOutlet weak var viewsLabel: UILabel!

    var content: Content! {
        didSet {
            self.refresh()
        }
    }

    var isBadgeVisible: Bool = false {
        didSet {
            if self.content.creator.isVerified && self.isBadgeVisible {
                self.verifiedBadgeImage.isHidden = false
            } else {
                self.verifiedBadgeImage.isHidden = true
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        let highlightView = UIView()
        highlightView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        self.selectedBackgroundView = highlightView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.fireCountLabel.text = "0"
        self.reactionCountLabel.text = "0"
        self.viewsLabel.text = "0"
        self.featuredLabel.isHidden = true
        self.repostLabel.isHidden = true
        self.featuredLabel.alpha = 1.0
        self.thumbnailImageView.af_cancelImageRequest()
        self.thumbnailImageView.image = nil
        self.titleLabel.text = nil
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        let fireBackground = self.fireCountLabel.superview?.backgroundColor
        let viewsBackground = self.viewsContainerView.backgroundColor
        super.setHighlighted(highlighted, animated: animated)
        if highlighted {
            self.fireCountLabel.superview?.backgroundColor = fireBackground
            self.viewsContainerView.backgroundColor = viewsBackground
        }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        let fireBackground = self.fireCountLabel.superview?.backgroundColor
        let viewsBackground = self.viewsContainerView.backgroundColor
        super.setHighlighted(selected, animated: animated)
        if selected {
            self.fireCountLabel.superview?.backgroundColor = fireBackground
            self.viewsContainerView.backgroundColor = viewsBackground
        }
    }

    private func refresh() {
        self.fireCountLabel.text = self.content.votes.countLabelShort
        self.reactionCountLabel.text = (self.content.relatedCount + self.content.commentCount).countLabelShort
        self.viewsLabel.text = self.content.views.countLabelShort
        if self.content.tags.contains("featured") {
            self.featuredLabel.alpha = 1.0
            self.featuredLabel.isHidden = false
        } else if self.content.tags.contains("exfeatured") {
            self.featuredLabel.alpha = 0.4
            self.featuredLabel.isHidden = false
        } else {
            self.featuredLabel.isHidden = true
        }
        if self.content.tags.contains("repost") {
            self.repostLabel.isHidden = false
        } else {
            self.repostLabel.isHidden = true
        }
        self.titleLabel.text = self.content.title ?? self.content.relatedTo?.title ?? ""
        self.usernameLabel.text = "@\(self.content.creator.username)"
        if let url = self.content.thumbnailURL {
            self.thumbnailImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
        } else {
            self.thumbnailImageView.af_cancelImageRequest()
            self.thumbnailImageView.image = #imageLiteral(resourceName: "relatedContent")
        }
    }
}
