import CoreVideo
import Metal
import QuartzCore
import UIKit

class Composer {
    typealias TexturePair = (cv: CVMetalTexture, metal: MTLTexture)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context: CIContext
    let device: MTLDevice
    let textureCache: CVMetalTextureCache

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        self.context = CIContext(mtlDevice: device)
        self.device = device
        self.commandQueue = self.device.makeCommandQueue()!
        self.commandQueue.label = "ComposerCommandQueue"

        let library = self.device.makeDefaultLibrary()!
        library.label = "ComposerLibrary"

        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.label = "ComposerRenderPipelineDescriptor"
        pipeline.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline.colorAttachments[0].isBlendingEnabled = true
        pipeline.colorAttachments[0].rgbBlendOperation = .add
        pipeline.colorAttachments[0].alphaBlendOperation = .add
        pipeline.colorAttachments[0].sourceRGBBlendFactor = .one
        pipeline.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipeline.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipeline.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline.vertexFunction = library.makeFunction(name: "basicVertex")
        pipeline.fragmentFunction = library.makeFunction(name: "basicFragment")
        self.pipelineState = try! self.device.makeRenderPipelineState(descriptor: pipeline)

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.device, nil, &cache)
        self.textureCache = cache!
    }

    func makeProvider(with image: UIImage) -> TextureProvider? {
        guard let cgi = image.cgImage, let context = CGContext.create(size: image.size, alpha: true) else {
            return nil
        }
        context.draw(cgi, in: CGRect(origin: .zero, size: image.size))
        guard let texture = self.makeTexture(fromContext: context, pixelFormat: .bgra8Unorm) else {
            return nil
        }
        texture.label = "UIImageTexture"
        return ConstantTexture(texture: texture)
    }

    func makeProvider(with text: String, font: UIFont) -> TextureProvider? {
        let attributedText = NSAttributedString(string: text, attributes: [
            NSAttributedStringKey.font: font,
            NSAttributedStringKey.foregroundColor: "F2F2F2".hexColor!,
            NSAttributedStringKey.strokeWidth: -3,
            NSAttributedStringKey.strokeColor: "212528".hexColor!,
            ])

        let size = attributedText.size()
        guard let context = CGContext.create(size: size, alpha: true) else {
            return nil
        }
        context.concatenate(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -size.height))

        UIGraphicsPushContext(context)
        attributedText.draw(at: .zero)
        UIGraphicsPopContext()

        guard let texture = self.makeTexture(fromContext: context, pixelFormat: .bgra8Unorm) else {
            return nil
        }
        texture.label = "NSAttributedStringTexture"
        return ConstantTexture(texture: texture)
    }

    /// Creates a quad using NDCs.
    func makeQuad(p1: (Float, Float), p2: (Float, Float), p3: (Float, Float), p4: (Float, Float),
                  uv1: (Float, Float) = (0, 0), uv2: (Float, Float) = (1, 1),
                  alpha: Float = 1) -> MTLBuffer
    {
        // TODO: Make this TL->TR->BR->BL.
        let quad = [p1.0, p1.1, 0, uv2.0, uv2.1, alpha,
                    p2.0, p2.1, 0, uv1.0, uv2.1, alpha,
                    p3.0, p3.1, 0, uv1.0, uv1.1, alpha,
                    p4.0, p4.1, 0, uv2.0, uv1.1, alpha,
                    p1.0, p1.1, 0, uv2.0, uv2.1, alpha,
                    p3.0, p3.1, 0, uv1.0, uv1.1, alpha]
        let buffer = self.device.makeBuffer(
            bytes: quad,
            length: quad.count * MemoryLayout.size(ofValue: quad[0]),
            options: [])!
        buffer.label = "QuadVertices"
        return buffer
    }

    func makeTexture(fromBuffer buffer: CVImageBuffer, pixelFormat: MTLPixelFormat) -> TexturePair? {
        var out: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            self.textureCache,
            buffer,
            nil,
            pixelFormat,
            CVPixelBufferGetWidth(buffer),
            CVPixelBufferGetHeight(buffer),
            0,
            &out)
        guard result == kCVReturnSuccess, let cvTexture = out else {
            return nil
        }
        guard let metalTexture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        let texture = self.makeTexture(width: metalTexture.width, height: metalTexture.height)
        texture.label = "CVImageBufferTexture"
        let commandBuffer = self.commandQueue.makeCommandBuffer()!
        let blitter = commandBuffer.makeBlitCommandEncoder()!
        blitter.copy(from: metalTexture, sourceSlice: 0, sourceLevel: 0,
                     sourceOrigin: MTLOriginMake(0, 0, 0),
                     sourceSize: MTLSizeMake(metalTexture.width, metalTexture.height, 1),
                     to: texture, destinationSlice: 0, destinationLevel: 0,
                     destinationOrigin: MTLOriginMake(0, 0, 0))
        blitter.endEncoding()
        commandBuffer.commit()
        return (cvTexture, texture)
    }

    func makeTexture(fromContext context: CGContext, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        guard let data = context.data else { return nil }
        let byteCount = context.bytesPerRow * context.height
        let buffer = self.device.makeBuffer(bytes: data, length: byteCount,
                                            options: [])!
        let texture = buffer.makeTexture(
            descriptor: .texture2DDescriptor(pixelFormat: pixelFormat,
                                             width: context.width,
                                             height: context.height,
                                             mipmapped: false),
            offset: 0, bytesPerRow: context.bytesPerRow)!
        texture.label = "CGContextTexture"
        return texture
    }

    func makeTexture(width: Int, height: Int, color: UIColor = .clear, usage: MTLTextureUsage = .shaderRead) -> MTLTexture {
        // Bytes per row must be a multiple of 64.
        let bytesPerRow = ((((width << 2) - 1) >> 6) + 1) << 6
        let buffer = self.device.makeBuffer(length: bytesPerRow * height, options: [.storageModeShared])!
        if color != .clear {
            // Turn UIColor into premultiplied BGRA8.
            var r = CGFloat(0), g = CGFloat(0), b = CGFloat(0), a = CGFloat(0)
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let value = (UInt32(a * 255) << 24 |
                UInt32(r * a * 255) << 16 |
                UInt32(g * a * 255) << 8 |
                UInt32(b * a * 255))
            // Access the buffer using a typed pointer.
            let count = buffer.length >> 2
            let typed = buffer.contents().bindMemory(to: UInt32.self, capacity: count)
            var yOffset = 0
            for _ in 0..<height {
                for x in 0..<width {
                    typed[yOffset + x] = value
                }
                yOffset += bytesPerRow >> 2
            }
            // Unbind the memory.
            typed.deinitialize(count: count)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false)
        descriptor.usage = usage
        let texture = buffer.makeTexture(
            descriptor: descriptor,
            offset: 0,
            bytesPerRow: bytesPerRow)!
        texture.label = "Basic\(width)x\(height)Texture"
        return texture
    }

    func makeWorker(size: CGSize) -> Worker {
        return Worker(composer: self, size: size)
    }

    // MARK: - Private

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState

    // MARK: -

    private struct CachedComposerLayer {
        let layer: ComposerLayer
        let semaphore = DispatchSemaphore(value: 1)

        var lastFrame: CGRect = .zero
        var lastLayout: ComposerLayout
        var lastTextureSize: CGSize = .zero
        var lastTransform: CGAffineTransform = .identity
        var texture: MTLTexture
        var vertices: MTLBuffer?

        init(_ layer: ComposerLayer, texture: MTLTexture) {
            self.layer = layer
            self.lastLayout = layer.layout
            self.texture = texture
        }

        mutating func getOrCreateVertices(worker: Worker) -> MTLBuffer {
            let layout = self.layer.layout
            let frame = self.layer.frame
            let transform = self.layer.transform
            let size = CGSize(width: CGFloat(self.texture.width), height: CGFloat(self.texture.height))
            if
                let vertices = self.vertices,
                self.lastFrame == frame,
                self.lastLayout == layout,
                self.lastTransform == transform,
                self.lastTextureSize == size
            {
                return vertices
            }
            // TODO: Direct manipulation of existing buffer if available.
            let vertices = worker.makeQuad(layout: layout, in: frame, basedOn: size, transform: transform)
            self.vertices = vertices
            self.lastFrame = frame
            self.lastLayout = layout
            self.lastTextureSize = size
            self.lastTransform = transform
            return vertices
        }
    }

    // MARK: -

    class Worker {
        let composer: Composer
        let size: CGSize

        init(composer: Composer, size: CGSize) {
            self.composer = composer
            self.size = size
            pthread_mutex_init(&self.mutex, nil)
            // Create empty textures to fall back to when a texture is missing.
            self.blackSquare = self.composer.makeTexture(width: 256, height: 256, color: .black)
            self.blackSquare.label = "BlackSquareTexture"
            self.blankSquare = self.composer.makeTexture(width: 256, height: 256)
            self.blankSquare.label = "BlankSquareTexture"
            // Create the target texture which everything will be composed into.
            self.composition = self.composer.makeTexture(
                width: Int(size.width),
                height: Int(size.height),
                usage: .renderTarget)
            self.composition.label = "ComposerCompositionTexture"
            self.unitQuad = composer.makeQuad(p1: (1, -1), p2: (-1, -1), p3: (-1, 1), p4: (1, 1))
        }

        deinit {
            pthread_mutex_destroy(&self.mutex)
        }

        func add(layer: ComposerLayer) {
            let square = layer.isOpaque ? self.blackSquare : self.blankSquare
            pthread_mutex_lock(&self.mutex)
            precondition(self.layerCache.count < 31, "Can only have at most 31 ComposerLayers at once")
            self.layerCacheOrder.append(self.layerCache.count)
            self.layerCache.append(CachedComposerLayer(layer, texture: square))
            pthread_mutex_unlock(&self.mutex)
        }

        func makeQuad(layout: ComposerLayout, in frame: CGRect, basedOn size: CGSize, transform: CGAffineTransform = .identity) -> MTLBuffer {
            // Cover quad with texture using aspect resize.
            let ratioW = frame.width / size.width
            let ratioH = frame.height / size.height
            let position: CGPoint, ratio: CGFloat
            switch layout {
            case let .cover(p):
                position = p
                ratio = ratioW > ratioH ? ratioW : ratioH
            case let .fit(p):
                position = p
                ratio = ratioW < ratioH ? ratioW : ratioH
            }
            let width = size.width * ratio
            let height = size.height * ratio
            let uncroppedFrame = CGRect(x: frame.minX + (frame.width - width) * position.x,
                                        y: frame.minY + (frame.height - height) * position.y,
                                        width: width, height: height)
            return self.makeQuad(with: uncroppedFrame, croppedTo: frame, transform: transform)
        }

        func makeQuad(with frame: CGRect, croppedTo visibleFrame: CGRect? = nil, transform: CGAffineTransform = .identity) -> MTLBuffer {
            let visibleFrame = (visibleFrame ?? frame).intersection(frame)
            precondition(!visibleFrame.isNull, "frame and visibleFrame do not intersect")
            let sx = 2 / self.size.width, sy = 2 / self.size.height
            let mx = visibleFrame.midX, my = visibleFrame.midY
            let cx = mx * sx - 1, cy = 1 - my * sy
            let points = [
                CGPoint(x: visibleFrame.maxX - mx, y: visibleFrame.maxY - my),
                CGPoint(x: visibleFrame.minX - mx, y: visibleFrame.maxY - my),
                CGPoint(x: visibleFrame.minX - mx, y: visibleFrame.minY - my),
                CGPoint(x: visibleFrame.maxX - mx, y: visibleFrame.minY - my),
                ]
                .map({ $0.applying(transform) })
                .map({ (p: CGPoint) -> (Float, Float) in (Float(cx + p.x * sx), Float(cy - p.y * sy)) })
            let u1 = Float((visibleFrame.minX - frame.minX) / frame.width)
            let v1 = Float((visibleFrame.minY - frame.minY) / frame.height)
            let u2 = Float((visibleFrame.maxX - frame.minX) / frame.width)
            let v2 = Float((visibleFrame.maxY - frame.minY) / frame.height)
            // TODO: Let the user specify alpha.
            return self.composer.makeQuad(p1: points[0], p2: points[1], p3: points[2], p4: points[3],
                                          uv1: (u1, v1), uv2: (u2, v2), alpha: 1)
        }

        func move(layer: ComposerLayer, toPositionOf other: ComposerLayer, above: Bool = false) {
            pthread_mutex_lock(&self.mutex)
            defer { pthread_mutex_unlock(&self.mutex) }
            var ao, bo: Int?
            for (i, ii) in self.layerCacheOrder.enumerated() {
                if self.layerCache[ii].layer === layer { ao = i }
                if self.layerCache[ii].layer === other { bo = above ? i + 1 : i }
            }
            guard let a = ao, let b = bo else {
                assertionFailure("Invalid call to Composer.move(...)")
                return
            }
            guard a != b else { return }
            self.layerCacheOrder.insert(self.layerCacheOrder[a], at: b)
            self.layerCacheOrder.remove(at: a < b ? a : a + 1)
        }

        func notifyIntentToWrite() -> Bool {
            return self.composeSemaphore.wait(timeout: .now()) == .success
        }

        func prepare(callback: @escaping () -> ()) {
            let time = CACurrentMediaTime()
            self.updateTextures(forHostTime: time, callback: {
                self.startComposing(forHostTime: time)
                callback()
            })
        }

        func startComposing(forHostTime time: CFTimeInterval) {
            // Calling this method twice before semaphore is signaled is a very bad idea.
            self.queue.async {
                self.composer.commandQueue.insertDebugCaptureBoundary()
                let commandBuffer = self.composer.commandQueue.makeCommandBuffer()!
                commandBuffer.label = "ComposerCommandBuffer"

                let renderPass = MTLRenderPassDescriptor()
                renderPass.colorAttachments[0].texture = self.composition

                let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)!
                encoder.label = "ComposerRenderCommandEncoder"
                encoder.setRenderPipelineState(self.composer.pipelineState)

                // TODO: This lock shouldn't need to be held this long.
                pthread_mutex_lock(&self.mutex)
                self.updateTextures(forHostTime: time, callback: {})

                encoder.setFragmentTexture(self.blackSquare, index: 0)
                encoder.setVertexBuffer(self.unitQuad, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)

                let indices = self.layerCacheOrder
                for i in indices {
                    guard !self.layerCache[i].layer.isHidden else { continue }
                    let vertices = self.layerCache[i].getOrCreateVertices(worker: self)
                    // TODO: Reduce to 1 draw call.
                    encoder.setFragmentTexture(self.layerCache[i].texture, index: 0)
                    encoder.setVertexBuffer(vertices, offset: 0, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
                }

                pthread_mutex_unlock(&self.mutex)

                encoder.endEncoding()
                commandBuffer.commit()
                self.composer.commandQueue.insertDebugCaptureBoundary()

                commandBuffer.waitUntilCompleted()
                self.composeSemaphore.signal()
            }
        }

        func writeTexture(into buffer: UnsafeMutableRawPointer, bytesPerRow: Int) {
            let region = MTLRegionMake2D(0, 0, Int(self.size.width), Int(self.size.height))
            self.composition.getBytes(buffer, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        }

        // MARK: - Private

        private let blackSquare: MTLTexture
        private let blankSquare: MTLTexture
        private let composition: MTLTexture
        private let composeSemaphore = DispatchSemaphore(value: 0)
        private let queue = DispatchQueue(label: "cam.reaction.ReactionCam.Composer.Worker." + UUID().uuidString,
                                          qos: .userInteractive,
                                          attributes: [.concurrent])
        private let unitQuad: MTLBuffer

        private var layerCache = [CachedComposerLayer]()
        private var layerCacheOrder = [Int]()
        private var mutex = pthread_mutex_t()

        private func updateTextures(forHostTime time: CFTimeInterval, callback: @escaping () -> ()) {
            // TODO: Make thread-safe if we support removing layers.
            let group = DispatchGroup()
            let indices = self.layerCacheOrder
            for i in indices {
                group.enter()
                self.queue.async {
                    defer { group.leave() }
                    let c = self.layerCache[i]
                    guard c.semaphore.wait(timeout: .now()) == .success else {
                        NSLog("%@", "WARNING: Skipped frame for layer \(i)")
                        return
                    }
                    defer { c.semaphore.signal() }
                    if c.layer.isHidden {
                        pthread_mutex_lock(&self.mutex)
                        self.layerCache[i].texture = c.layer.isOpaque ? self.blackSquare : self.blankSquare
                        pthread_mutex_unlock(&self.mutex)
                        return
                    }
                    guard let t = c.layer.provider.provideTexture(renderer: self.composer, forHostTime: time) else {
                        return
                    }
                    pthread_mutex_lock(&self.mutex)
                    self.layerCache[i].texture = t
                    pthread_mutex_unlock(&self.mutex)
                }
            }
            self.queue.async {
                group.wait()
                callback()
            }
        }
    }
}
