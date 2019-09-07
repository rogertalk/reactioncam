import UIKit

class OriginalContentView: UIView {
    static let defaultHeight = CGFloat(256)

    var content: OriginalContent? {
        didSet {
            guard let content = self.content else {
                self.reset()
                return
            }

            // Set up the title and thumbnail of the original content.
            self.titleLabel.text = content.title
            if let url = content.thumbnailURL {
                self.thumbnailImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
                self.moreImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))

            }

            // Set up metadata under the title.
            if let creator = content.creator {
                self.creatorLabel.text = "@\(creator.username)"
                self.creatorLabel.isHidden = false
                self.creatorVerifiedImage.isHidden = !creator.isVerified
                self.reactionCountLabel.text = " • \(content.relatedCount) reactions"
            } else {
                self.creatorLabel.isHidden = true
                self.creatorVerifiedImage.isHidden = true
                self.reactionCountLabel.text = "\(content.relatedCount) reactions"
            }

            // Set up related views.
            self.firstReactionView.isHidden = true
            self.secondReactionView.isHidden = true
            self.thirdReactionView.isHidden = true
            self.moreViewContainer.isHidden = true

            let related = content.related
            // TODO: better logic for this (should use a collectionview)
            if related.count > 0, let url = related.first?.thumbnailURL {
                self.firstReactionImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
                self.firstReactionView.isHidden = false
            }
            if related.count > 1, let url = related[1].thumbnailURL {
                self.secondReactionImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
                self.secondReactionView.isHidden = false
            }
            if related.count > 2, let url = related[2].thumbnailURL {
                self.thirdReactionImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
                self.thirdReactionView.isHidden = false
            }
            if content.relatedCount > 3 {
                self.moreButton.setTitle("+ \((content.relatedCount - 3).countLabelShort) more", for: .normal)
                self.moreViewContainer.isHidden = false
            }
        }
    }

    var source = "Unknown"

    @IBOutlet weak var creatorLabel: UILabel!
    @IBOutlet weak var creatorVerifiedImage: UIImageView!
    @IBOutlet weak var firstReactionView: UIView!
    @IBOutlet weak var firstReactionImageView: UIImageView!
    @IBOutlet weak var moreImageView: UIImageView!
    @IBOutlet weak var moreButton: UIButton!
    @IBOutlet weak var moreViewContainer: UIView!
    @IBOutlet weak var reactionCountLabel: UILabel!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var secondReactionView: UIView!
    @IBOutlet weak var secondReactionImageView: UIImageView!
    @IBOutlet weak var thirdReactionView: UIView!
    @IBOutlet weak var thirdReactionImageView: UIImageView!
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initialize()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initialize()
    }

    @IBAction func reactionTapped(_ sender: LoaderButton) {
        guard let content = self.content else {
            return
        }

        let selectedContent = content.related[sender.tag]
        if let related = self.related {
            TabBarController.select(contentList: related, presetContentId: selectedContent.id)
        } else {
            sender.isLoading = true
            ContentService.instance.getRelatedContentList(for: content, sortBy: "top") {  results, _ in
                sender.isLoading = false
                guard let related = results else {
                    return
                }
                self.related = related
                TabBarController.select(contentList: related, presetContentId: selectedContent.id)
            }
        }
    }

    @IBAction func contentTouchDown(_ sender: Any) {
        UIView.animate(withDuration: 0.1, delay: 0, options: .beginFromCurrentState, animations: {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        })
    }

    @IBAction func contentTouchUp(_ sender: Any) {
        UIView.animate(withDuration: 0.1, delay: 0, options: .beginFromCurrentState, animations: {
            self.transform = .identity
        })
    }

    @IBAction func createReactionTapped(_ sender: Any) {
        guard let content = self.content, let url = content.originalURL else {
            return
        }
        TabBarController.showCreate(url: url, ref: content.ref, relevantUsername: nil,
                                    source: "Original Content Item Create Reaction Action")
    }

    @IBAction func moreReactionsTapped(_ sender: Any) {
        guard let content = self.content else {
            return
        }
        TabBarController.select(originalContent: content, source: "\(self.source) More")
    }
    
    // MARK: - Private

    private var related: [Content]? = nil

    private func initialize() {
        guard let view = Bundle.main.loadNibNamed("OriginalContentView", owner: self, options: nil)?[0] as? UIView else {
            return
        }
        self.addSubview(view)
        view.frame = self.bounds
        
        self.scrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    }

    private func reset() {
        self.related = nil

        self.scrollView.setContentOffset(CGPoint(x: -16, y: 0), animated: false)
        
        self.titleLabel.text = nil
        self.thumbnailImageView.image = #imageLiteral(resourceName: "relatedContent")
        self.thumbnailImageView.af_cancelImageRequest()
        self.moreImageView.image = #imageLiteral(resourceName: "relatedContent")
        self.moreImageView.af_cancelImageRequest()
        
        // TODO: Replace with collection view cells
        self.firstReactionImageView.af_cancelImageRequest()
        self.secondReactionImageView.af_cancelImageRequest()
        self.thirdReactionImageView.af_cancelImageRequest()
        self.firstReactionImageView.image = #imageLiteral(resourceName: "relatedContent")
        self.secondReactionImageView.image = #imageLiteral(resourceName: "relatedContent")
        self.thirdReactionImageView.image = #imageLiteral(resourceName: "relatedContent")
    }
}
