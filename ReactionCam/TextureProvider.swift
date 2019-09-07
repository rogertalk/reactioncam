import CoreGraphics
import Metal

protocol TextureProvider {
    func provideTexture(renderer: Composer, forHostTime time: CFTimeInterval) -> MTLTexture?
}
