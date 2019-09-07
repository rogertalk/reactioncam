import UIKit

/// The view to show particles
public class CheerView: UIView {
    public enum Particle {
        case confetti
        case image([UIImage])
        case text(CGSize, [NSAttributedString])
    }

    public struct Config {
        /// Specify the particle shapes.
        public var particle: Particle = .confetti

        /// The list of available colors. This will be shuffled.
        public var colors: [UIColor] = [
            UIColor.red,
            UIColor.green,
            UIColor.blue,
            UIColor.yellow,
            UIColor.purple,
            UIColor.orange,
            UIColor.cyan
        ]

        /// Customize the cells.
        public var customize: ((CAEmitterLayer, [CAEmitterCell]) -> ())?

        public init() {}
    }

    public var config = Config()

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()

        isUserInteractionEnabled = false
    }

    /// Start animation
    public func start() {
        stop()

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2.0, y: 0)
        emitter.emitterShape = kCAEmitterLayerLine
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.renderMode = kCAEmitterLayerAdditive

        let colors = config.colors.shuffled()
        var cells = [CAEmitterCell]()

        zip(pickImages(), colors.shuffled()).forEach { image, color in
            let cell = CAEmitterCell()
            cell.birthRate = 20
            cell.lifetime = 20.0
            cell.lifetimeRange = 10
            cell.velocity = 250
            cell.velocityRange = 50
            cell.emissionLongitude = CGFloat.pi
            cell.emissionRange = CGFloat.pi * 0.2
            cell.spinRange = 5
            cell.scale = 0.3
            cell.scaleRange = 0.2
            cell.color = color.cgColor
            cell.alphaSpeed = -0.1
            cell.contents = image.cgImage
            cell.xAcceleration = 20
            cell.yAcceleration = 50
            cell.redRange = 0.8
            cell.greenRange = 0.8
            cell.blueRange = 0.8
            cells.append(cell)
        }

        emitter.emitterCells = cells
        emitter.beginTime = CACurrentMediaTime()

        self.config.customize?(emitter, cells)

        self.layer.addSublayer(emitter)
        self.emitter = emitter
    }

    public func stop() {
        self.emitter?.birthRate = 0
    }

    // MARK: - Private

    private var emitter: CAEmitterLayer?

    private func pickImages() -> [UIImage] {
        let generator = ImageGenerator()
        switch config.particle {
        case .confetti:
            let parts = [
                generator.rectangle(),
                generator.circle(),
                generator.triangle(),
                generator.curvedQuadrilateral(),
            ]
            return parts.compactMap({ $0 })
        case .image(let images):
            return images
        case .text(let size, let strings):
            return strings.compactMap({ generator.generate(size: size, string: $0) })
        }
    }
}

