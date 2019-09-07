import UIKit

class UploadCell: UICollectionViewCell {
    @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!

    var upload: UploadJob! {
        didSet {
            self.activityIndicatorView.startAnimating()
            if self.upload.bytes > 0 {
                self.progressView.progress = Float(self.upload.progress) / Float(self.upload.bytes)
            } else {
                self.progressView.progress = 0
            }
            if self.upload.token != nil {
                self.statusLabel.text = "Uploading…"
            } else {
                self.statusLabel.text = "⚠️ Upload failed to start"
            }
        }
    }

    // MARK: - UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()
        self.progressView.progress = 0
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
}
