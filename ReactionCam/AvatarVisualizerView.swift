import AlamofireImage

protocol VisualizerDelegate: class {
    var audioLevel: Float { get }
}

class AvatarVisualizerView: UIView {
    weak var visualizerDelegate: VisualizerDelegate?

    var isActive: Bool = false {
        didSet {
            self.visualizerUpdateTimer.isPaused = !self.isActive
            self.visualizer.isHidden = !self.isActive
        }
    }

    override func awakeFromNib() {
        self.layoutIfNeeded()

        // Visualizer
        self.visualizer = UIView(frame:
            CGRect(x: 3, y: 3, width: self.bounds.width - 6, height: self.bounds.height - 6))
        self.visualizer.backgroundColor = UIColor.white.withAlphaComponent(0.4)
        self.visualizer.borderColor = UIColor.white.withAlphaComponent(0.5)
        self.visualizer.layer.borderWidth = 0.5
        self.visualizer.layer.cornerRadius = self.visualizer.frame.size.width / 2
        self.addSubview(self.visualizer)

        // Avatar
        self.avatarImageView = UIImageView(frame: self.bounds)
        self.avatarImageView.layer.cornerRadius = self.avatarImageView.frame.width / 2
        self.avatarImageView.clipsToBounds = true
        self.avatarImageView.image = UIImage(named: "single")
        self.addSubview(self.avatarImageView)

        // Update timer
        self.visualizerUpdateTimer = CADisplayLink(target: self, selector: #selector(AvatarVisualizerView.updateAudioVisualizer))
        self.visualizerUpdateTimer.isPaused = true
        self.visualizerUpdateTimer.add(to: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
    }

    deinit {
        self.visualizerUpdateTimer.invalidate()
        self.visualizerUpdateTimer = nil
    }

    func setImage(url: URL) {
        self.avatarImageView.af_setImage(withURL: url)
    }

    private var avatarImageView: UIImageView!
    private var visualizer: UIView!
    private var visualizerScale = CGFloat(0)
    private var visualizerUpdateTimer: CADisplayLink!

    @objc private dynamic func updateAudioVisualizer() {
        guard let scale = self.visualizerDelegate.flatMap({ CGFloat($0.audioLevel) }) else {
            return
        }
        self.visualizerScale = scale < self.visualizerScale ? (self.visualizerScale * 8 + scale) / 9 : scale
        self.visualizer.transform = CGAffineTransform(scaleX: self.visualizerScale, y: self.visualizerScale)
        self.visualizer.center = self.avatarImageView.center
    }
}
