import CoreGraphics
import Metal

class ConstantTexture: TextureProvider {
    let size: CGSize
    let texture: MTLTexture

    init(texture: MTLTexture) {
        self.size = CGSize(width: texture.width, height: texture.height)
        self.texture = texture
    }

    // MARK: - TextureProvider

    func provideTexture(renderer: Composer, forHostTime time: CFTimeInterval) -> MTLTexture? {
        return self.texture
    }
}
