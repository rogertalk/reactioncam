import CoreGraphics

class ComposerLayer: CustomDebugStringConvertible {
    let name: String

    var frame: CGRect
    var isHidden = false
    var isOpaque = false
    var layout = ComposerLayout.coverCenter
    var provider: TextureProvider
    var transform = CGAffineTransform.identity

    init(_ name: String, frame: CGRect, provider: TextureProvider) {
        self.name = name
        self.frame = frame
        self.provider = provider
    }

    // MARK: - CustomDebugStringConvertible

    var debugDescription: String {
        return "<ComposerLayer \"\(self.name)\">"
    }
}
