import UIKit

class ContentSuggestionView: UIView {
    @IBOutlet weak var reactionsLabel: UILabel!
    @IBOutlet weak var thumbnailButton: UIButton!
    @IBOutlet weak var titleLabel: UILabel!

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initialize()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initialize()
    }

    private func initialize() {
        guard let view = Bundle.main.loadNibNamed("ContentSuggestionView", owner: self, options: nil)?[0] as? UIView else {
            return
        }
        self.addSubview(view)
        view.frame = self.bounds
        self.thumbnailButton.imageView?.contentMode = .scaleAspectFill
        self.thumbnailButton.contentHorizontalAlignment = .fill
        self.thumbnailButton.contentVerticalAlignment = .fill
    }
}
