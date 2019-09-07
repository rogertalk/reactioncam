import AVFoundation
import CoreImage
import Metal

class CameraTexture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, TextureProvider {
    var filter: CIFilter?
    private(set) var size: CGSize = .zero

    override init() {
        pthread_mutex_init(&self.mutex, nil)
        super.init()
        Recorder.instance.hookCameraOutput(delegate: self)
    }

    deinit {
        pthread_mutex_destroy(&self.mutex)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        pthread_mutex_lock(&self.mutex)
        defer { pthread_mutex_unlock(&self.mutex) }
        self.changed = true
        self.lastBuffer = sampleBuffer
    }

    // MARK: - TextureProvider

    func provideTexture(renderer: Composer, forHostTime time: CFTimeInterval) -> MTLTexture? {
        pthread_mutex_lock(&self.mutex)
        defer { pthread_mutex_unlock(&self.mutex) }
        guard
            self.changed,
            let sampleBuffer = self.lastBuffer,
            let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return self.lastTexturePair?.metal }
        self.changed = false
        CVPixelBufferLockBaseAddress(buffer, [.readOnly])
        defer { CVPixelBufferUnlockBaseAddress(buffer, [.readOnly]) }
        guard let filter = self.filter else {
            guard let pair = renderer.makeTexture(fromBuffer: buffer, pixelFormat: .bgra8Unorm) else {
                self.lastTexturePair = nil
                self.size = .zero
                return nil
            }
            let (cvTexture, texture) = pair
            self.lastTexturePair = (cv: cvTexture, metal: texture)
            self.size = CGSize(width: texture.width, height: texture.height)
            return texture
        }
        let image = CIImage(cvImageBuffer: buffer)
        let bounds = image.extent
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -bounds.height)
        filter.setValue(image.transformed(by: transform), forKey: kCIInputImageKey)
        guard let outputImage = filter.outputImage else {
            NSLog("%@", "WARNING: Failed to get CIFilter outputImage")
            return self.lastTexturePair?.metal
        }
        let texture = renderer.makeTexture(width: Int(bounds.width), height: Int(bounds.height),
                                           usage: [.shaderRead, .shaderWrite])
        renderer.context.render(outputImage, to: texture,
                                commandBuffer: nil,
                                bounds: bounds,
                                colorSpace: renderer.colorSpace)
        self.lastTexturePair = (nil, texture)
        self.size = bounds.size
        return texture
    }

    // MARK: - Private

    private var changed = false
    private var lastBuffer: CMSampleBuffer?
    private var lastTexturePair: (cv: CVMetalTexture?, metal: MTLTexture)?
    private var mutex = pthread_mutex_t()
}
