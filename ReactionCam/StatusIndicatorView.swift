import UIKit

class StatusIndicatorView: UIView {

    @IBOutlet weak var confirmationLabel: UILabel!
    @IBOutlet weak var loader: UIActivityIndicatorView!
    @IBOutlet weak var titleLabel: UILabel!

    static func create(container: UIView) -> StatusIndicatorView {
        let view = Bundle.main.loadNibNamed("StatusIndicatorView", owner: self, options: nil)?[0] as! StatusIndicatorView
        view.center = container.center
        view.isHidden = true
        view.alpha = 0
        container.addSubview(view)
        return view
    }

    override func layoutSubviews() {
        self.frame.size = CGSize(width: 130, height: 130)
        if let container = self.superview {
            self.center = container.center
        }
        super.layoutSubviews()
    }

    func hide() {
        self.timer?.invalidate()
        self.timer = nil
        self.hideAnimated() {
            self.loader.stopAnimating()
            self.confirmationLabel.isHidden = true
        }
    }

    func showConfirmation(title: String? = nil, completion: (() -> ())? = nil) {
        self.loader.stopAnimating()
        self.titleLabel.text = title
        self.confirmationLabel.font = UIFont.materialFont(ofSize: 47)
        self.confirmationLabel.isHidden = false
        self.showTemporary(completion: completion)
    }

    func showLoading(title: String? = nil, delay: TimeInterval = 0) {
        self.titleLabel.text = title
        guard self.isHidden else {
            return
        }
        self.confirmationLabel.isHidden = true
        self.loader.startAnimating()
        self.show(delay: delay)
    }

    // MARK: - Private

    private var timer: Timer?

    private func show(delay: TimeInterval) {
        self.timer?.invalidate()
        guard delay > 0 else {
            self.showAnimated()
            return
        }
        self.timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            self.showAnimated()
            self.timer = nil
        }
    }

    private func showTemporary(completion: (() -> ())? = nil) {
        self.showAnimated()
        // Automatically hide after a short delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            completion?()
            self.hide()
        }
    }
}
