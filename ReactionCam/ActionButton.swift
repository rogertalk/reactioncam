import UIKit

class ActionButton: BadgeButton {
    let overlayLabel: UILabel

    override init(frame: CGRect) {
        let label = UILabel(frame: .zero)
        self.overlayLabel = label
        super.init(frame: frame)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.contentMode = .center
        label.font = .systemFont(ofSize: 10)
        label.frame = self.bounds
        label.isHidden = true
        label.isUserInteractionEnabled = false
        label.textAlignment = .center
        self.addSubview(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.addSubview(self.overlayLabel)
    }
}
