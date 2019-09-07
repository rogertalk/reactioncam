import Metal
import UIKit

class UIViewTexture: TextureProvider {
    private(set) weak var view: UIView?

    init(view: UIView) {
        self.view = view
    }

    // MARK: - TextureProvider

    func provideTexture(renderer: Composer, forHostTime time: CFTimeInterval) -> MTLTexture? {
        guard let view = self.view else {
            return nil
        }
        var size = CGSize.zero
        DispatchQueue.main.sync {
            if view.window != nil {
                size = view.bounds.size
            }
        }
        guard size != .zero else {
            return nil
        }
        let context = self.getContext(for: size)
        DispatchQueue.main.sync {
            UIGraphicsPushContext(context)
            let rect = CGRect(origin: .zero, size: view.bounds.size)
            view.drawHierarchy(in: rect, afterScreenUpdates: false)
            UIGraphicsPopContext()
        }
        return renderer.makeTexture(fromContext: context, pixelFormat: .bgra8Unorm)
    }

    // MARK: - Private

    private var context: CGContext?

    private func getContext(for size: CGSize) -> CGContext {
        let scale = UIScreen.main.scale
        let native = size.applying(CGAffineTransform(scaleX: scale, y: scale))
        if let context = self.context, context.width == Int(native.width) && context.height == Int(native.height) {
            return context
        }
        let context = CGContext.create(size: native)!
        context.concatenate(CGAffineTransform(scaleX: scale, y: -scale).translatedBy(x: 0, y: -size.height))
        self.context = context
        return context
    }
}
