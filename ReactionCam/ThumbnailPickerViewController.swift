import AVFoundation
import UIKit

protocol ThumbnailPickerDelegate: class {
    func thumbnailPicker(_ picker: ThumbnailPickerViewController, didSelectThumbnail url: UIImage)
}

class ThumbnailPickerViewController: UIViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate, AMVideoRangeSliderDelegate {
    
    let minimumDuration: Double = 5
    
    weak var delegate: ThumbnailPickerDelegate?
    
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var playerContainer: UIView!
    @IBOutlet weak var rangeSlider: AMVideoRangeSlider!
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    func load(asset: AVURLAsset) {
        self.video = asset
        self.updateSliderConfig()
        NotificationCenter.default.removeObserver(self)
        self.player.pause()
        let item = AVPlayerItem(asset: asset)
        item.add(self.playerOutput)
        self.player.replaceCurrentItem(with: item)
        
        self.rangeSlider.videoAsset = asset
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ThumbnailPickerViewController.playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: self.player.currentItem)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.imagePicker.delegate = self

        self.rangeSlider.delegate = self
        self.rangeSlider.sliderTintColor = .uiRed
        self.rangeSlider.middleThumbTintColor = .uiYellow
        self.rangeSlider.isSelectionEnabled = false
        if let asset = self.video {
            self.rangeSlider.videoAsset = asset
        }

        self.player.actionAtItemEnd = .pause
        
        let preview = AVPlayerLayer(player: self.player)
        preview.backgroundColor = UIColor.clear.cgColor
        preview.masksToBounds = false
        preview.videoGravity = .resizeAspect
        self.playerContainer.layer.addSublayer(preview)
        self.playerLayer = preview
        
        self.playerOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        
        self.timeObserver = self.player.addPeriodicTimeObserver(forInterval: CMTimeMake(1, 60), queue: DispatchQueue.main) {
            [weak self] time -> Void in
            guard
                let vc = self,
                vc.player.rate > 0,
                let duration = vc.player.currentItem?.duration.seconds,
                !duration.isNaN,
                !duration.isZero
                else { return }
            vc.rangeSlider.middleValue = time.seconds / duration
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.playerLayer?.frame = self.playerContainer.bounds
    }
    
    // MARK: - Actions
    
    @IBAction func customTapped(_ sender: Any) {
        Logging.log("Thumbnail Picker Action", ["Action": "Cancel"])
        self.present(self.imagePicker, animated: true)
    }
    
    @IBAction func closeTapped(_ sender: Any) {
        Logging.log("Thumbnail Picker Action", ["Action": "Cancel"])
        self.player.replaceCurrentItem(with: nil)
        self.dismiss(animated: true)
    }
    
    @IBAction func playTapped(_ sender: Any) {
        let isPaused = self.player.rate == 0
        isPaused ? self.play() : self.pause()
        Logging.log("Thumbnail Picker Action", ["Action": isPaused ? "Play" : "Pause"])
    }
    
    @IBAction func saveTapped(_ sender: Any) {
        Logging.log("Thumbnail Picker Action", ["Action": "Save"])
        guard let thumbnail = self.getSelectedFrame() else {
            return
        }
        UIImageWriteToSavedPhotosAlbum(thumbnail, nil, nil, nil)
        self.statusIndicatorView.showConfirmation(title: "Saved to Photos")
    }
    
    @IBAction func selectTapped(_ sender: Any) {
        Logging.log("Thumbnail Picker Action", ["Action": "Select"])
        guard let image = self.getSelectedFrame() else {
            return
        }
        self.player.replaceCurrentItem(with: nil)
        self.delegate?.thumbnailPicker(self, didSelectThumbnail: image)
    }
    
    private func getSelectedFrame() -> UIImage? {
        guard let asset = self.player.currentItem?.asset,
            let duration = self.player.currentItem?.duration else {
                return nil
        }

        let time = CMTime(seconds: self.rangeSlider.middleValue * duration.seconds, preferredTimescale: 44100)
        if let eaglContext = EAGLContext(api: .openGLES2), let buffer = self.playerOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
            let ciContext = CIContext(eaglContext: eaglContext)
            let image = CIImage(cvPixelBuffer: buffer)
            if let outputImageRef = ciContext.createCGImage(image, from: image.extent) {
                return UIImage(cgImage: outputImageRef)
            }
        }
        return asset.generateThumbnail(at: time)
    }

    // MARK: - AMVideoRangeSliderDelegate
    
    func rangeSliderLowerThumbValueChanged() {}
    
    func rangeSliderUpperThumbValueChanged() {}
    
    func rangeSliderMiddleThumbValueChanged() {
        self.pause()
        self.seek(to: self.rangeSlider.middleValue)
    }
    
    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        guard
            let image = info[UIImagePickerControllerOriginalImage] as? UIImage else
        {
            Logging.log("Custom Thumbnail Action", ["Result": "Cancel"])
            picker.dismiss(animated: true)
            return
        }
        
        picker.dismiss(animated: true)
        self.player.replaceCurrentItem(with: nil)
        self.delegate?.thumbnailPicker(self, didSelectThumbnail: image)
        Logging.log("Custom Thumbnail Action", ["Result": "PickedImage"])
    }

    // MARK: - Private
    
    private let imagePicker = UIImagePickerController()
    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer?
    private var playerOutput: AVPlayerItemVideoOutput!
    
    private var statusIndicatorView: StatusIndicatorView!
    private var timeObserver: Any?
    private var video: AVURLAsset?
    
    private func pause() {
        self.playButton.setTitle("play_arrow", for: .normal)
        self.player.pause()
    }
    
    private func play() {
        guard self.player.rate == 0 else {
            return
        }
        self.seek(to: self.rangeSlider.middleValue)
        self.playButton.setTitle("pause", for: .normal)
        self.player.play()
    }
    
    @objc private dynamic func playerItemDidReachEnd() {
        DispatchQueue.main.async {
            self.pause()
        }
    }
    
    private func seek(to value: Double) {
        guard let duration = self.player.currentItem?.duration else {
            return
        }
        self.player.seek(
            to: CMTime(seconds: value * duration.seconds,
                       preferredTimescale: 44100),
            toleranceBefore: kCMTimeZero,
            toleranceAfter: kCMTimeZero)
    }
    
    private func updateSliderConfig() {
        guard let asset = self.video, let slider = self.rangeSlider else {
            return
        }
        slider.videoAsset = asset
    }
}

