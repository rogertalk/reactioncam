import UIKit

class PinnedContentCell: SeparatorCell {
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var featuredLabel: UILabel!
    @IBOutlet weak var repostLabel: UIView!

    var content: PinnedContent! {
        didSet {
            self.refresh()
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
        self.featuredLabel.isHidden = true
        self.repostLabel.isHidden = true
        self.featuredLabel.alpha = 1
        self.thumbnailImageView.af_cancelImageRequest()
        self.thumbnailImageView.image = nil
        self.titleLabel.text = nil
    }

    private func refresh() {
        if self.content.tags.contains("featured") {
            self.featuredLabel.alpha = 1
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
        if let url = self.content.thumbnailURL {
            self.thumbnailImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
        } else {
            self.thumbnailImageView.af_cancelImageRequest()
            self.thumbnailImageView.image = #imageLiteral(resourceName: "relatedContent")
        }
    }
}
