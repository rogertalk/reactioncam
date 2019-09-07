import AlamofireImage
import AVFoundation
import UIKit

protocol RecordPreviewViewDelegate: class {
    func recordPreviewViewWasTapped(_ view: RecordPreviewView)
}

class RecordPreviewView: UIView {

    var contentImageURL: URL? {
        didSet {
            guard self.contentImageURL != oldValue else {
                return
            }
            guard let url = self.contentImageURL else {
                self.contentView.af_cancelImageRequest()
                self.contentView.image = #imageLiteral(resourceName: "relatedContent")
                return
            }
            let idealURL = url.absoluteString.replacingOccurrences(of: "/hqdefault.jpg", with: "/maxresdefault.jpg")
            if oldValue?.absoluteString == idealURL {
                // If we already loaded up a higher resolution thumbnail, don't change.
                return
            }
            self.contentView.af_setImage(withURL: url)
        }
    }

    weak var delegate: RecordPreviewViewDelegate?

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.layer.cornerRadius = 8
        self.borderColor = UIColor.white.withAlphaComponent(0.3)
        self.layer.borderWidth = 4
        self.clipsToBounds = true

        self.contentView.backgroundColor = .black
        self.contentView.clipsToBounds = true
        self.contentView.contentMode = .scaleAspectFill
        self.contentView.frame = .zero
        self.addSubview(self.contentView)

        if !SettingsManager.didChangeLayout {
            self.label.font = .boldSystemFont(ofSize: 12)
            self.label.numberOfLines = 0
            self.label.text = "Tap to change"
            self.label.textAlignment = .center
            self.label.textColor = .white
            self.label.setHeavyShadow()
        }

        self.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(RecordPreviewView.handlePan)))
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(RecordPreviewView.handleTap)))
    }

    func hookPreview() {
        let layer = Recorder.instance.hookCameraPreview()
        self.layer.insertSublayer(layer, below: self.contentView.layer)
        layer.frame = self.bounds
        self.cameraLayer = layer
    }

    func updateFrames(config: PipConfig, camera: CGSize, content: CGSize, in container: CGSize, orientation: UIDeviceOrientation, area: CGFloat = 14400) {
        guard let sb = self.superview?.bounds else {
            return
        }
        // Calculate a new size with the correct ratio, maintaining a constant area.
        let ratio = container.width / container.height
        let width = sqrt(area * ratio)
        let size = CGSize(width: round(width), height: round(area / width))
        // Set up UI transforms to account for device orientation.
        let uiSize: CGSize
        let uiTransform: CGAffineTransform
        let mirrored: Bool
        switch orientation {
        case .landscapeLeft:
            uiSize = CGSize(width: size.height, height: size.width)
            if Recorder.instance.configuration == .frontCamera {
                // Mirrored.
                mirrored = true
                uiTransform = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: size.height, ty: size.width)
            } else {
                mirrored = false
                uiTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0)
            }
        case .landscapeRight:
            uiSize = CGSize(width: size.height, height: size.width)
            if Recorder.instance.configuration == .frontCamera {
                // Mirrored.
                mirrored = true
                uiTransform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
            } else {
                mirrored = false
                uiTransform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.width)
            }
        default:
            mirrored = false
            uiSize = size
            uiTransform = .identity
        }
        // Reposition the frame, anchoring to the closest edges.
        let f = self.frame
        let origin = CGPoint(x: self.center.x < sb.midX ? f.minX : f.minX + f.width - uiSize.width,
                             y: self.center.y < sb.midY ? f.minY : f.minY + f.height - uiSize.height)
        self.frame = CGRect(origin: origin, size: uiSize)
        // Reposition camera and content previews.
        if config.isContentAbove {
            self.layer.insertSublayer(self.contentView.layer, above: self.cameraLayer)
        } else {
            self.layer.insertSublayer(self.contentView.layer, below: self.cameraLayer)
        }
        let margin = ceil(10 / container.width * size.width)
        let frames = config.framesFor(camera: camera, content: content, in: size, margin: margin)
        self.cameraLayer?.frame = frames.camera.applying(uiTransform)
        if frames.content.width > 0 && frames.content.height > 0 {
            self.contentView.transform = mirrored ? uiTransform.scaledBy(x: -1, y: 1) : uiTransform
            self.contentView.frame = frames.content.applying(uiTransform)
            self.contentView.isHidden = false
        } else {
            self.contentView.isHidden = true
        }
        if !SettingsManager.didChangeLayout {
            self.label.frame = self.bounds.insetBy(dx: 8, dy: 8)
            self.addSubview(self.label)
        }
    }

    // MARK: - Private

    private let contentView = UIImageView(image: #imageLiteral(resourceName: "relatedContent"))
    private let label = UILabel()

    private var cameraLayer: AVCaptureVideoPreviewLayer?

    @objc private dynamic func handlePan(recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        self.center = CGPoint(
            x: self.center.x + translation.x,
            y: self.center.y + translation.y
        )
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private dynamic func handleTap(recognizer: UITapGestureRecognizer) {
        SettingsManager.didChangeLayout = true
        self.label.removeFromSuperview()
        self.delegate?.recordPreviewViewWasTapped(self)
    }
}
