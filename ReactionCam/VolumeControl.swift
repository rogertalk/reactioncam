import AVFoundation
import UIKit

fileprivate let volumeBlocks = 8

class VolumeControl: UIView {
    init() {
        let background = CALayer()
        background.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
        self.background = background
        self.blocks = (0..<volumeBlocks).map({ _ in
            let layer = CALayer()
            layer.backgroundColor = UIColor.white.cgColor
            layer.opacity = 0
            return layer
        })
        super.init(frame: .zero)
        self.alpha = 0
        self.layer.addSublayer(background)
        self.blocks.forEach(self.layer.addSublayer)
        self.frame = CGRect(x: 0, y: 0, width: UIApplication.shared.keyWindow!.bounds.width, height: 5)
        self.autoresizingMask = [.flexibleWidth]
        VolumeMonitor.instance.routeChange.addListener(self, method: VolumeControl.handleRouteChange)
        VolumeMonitor.instance.volumeChange.addListener(self, method: VolumeControl.show)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.background.frame = self.bounds
        let blockWidth = ceil(self.frame.width / CGFloat(volumeBlocks)) - 1
        for (i, block) in self.blocks.enumerated() {
            let start = 1 + (blockWidth + 1) * CGFloat(i)
            block.frame = CGRect(x: start, y: 1, width: min(self.frame.width - start - 1, blockWidth), height: 3)
        }
    }

    func show(withVolume volume: Float) {
        guard let parent = self.superview else {
            return
        }
        let step = Int(round(Float(volumeBlocks * 2) * volume))
        let endIndex = step / 2
        for (i, block) in self.blocks.enumerated() {
            if i < endIndex {
                block.opacity = 1
            } else if i == endIndex && step % 2 == 1 {
                block.opacity = 0.5
            } else {
                block.opacity = 0
            }
        }
        parent.bringSubview(toFront: self)
        self.alpha = 1
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            UIView.animate(withDuration: 0.3) { self.alpha = 0 }
        }
    }

    // MARK: - Private

    private let background: CALayer
    private let blocks: [CALayer]
    private var timer: Timer?

    private func handleRouteChange(volume: Float) {
        // Show volume after switching output.
        self.show(withVolume: volume)
    }
}
