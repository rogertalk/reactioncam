import MetalKit

class CameraPreview: MTKView {
    init(frame: CGRect, composer: Composer, texture: CameraTexture) {
        self.commandQueue = composer.device.makeCommandQueue()!

        let library = composer.device.makeDefaultLibrary()!
        library.label = "ComposerLibrary"

        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.label = "ComposerRenderPipelineDescriptor"
        pipeline.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline.vertexFunction = library.makeFunction(name: "basicVertex")
        pipeline.fragmentFunction = library.makeFunction(name: "basicFragment")
        self.pipelineState = try! composer.device.makeRenderPipelineState(descriptor: pipeline)

        self.composer = composer
        self.provider = texture
        self.quad = composer.makeQuad(p1: (-1, -1), p2: (1, -1), p3: (1, 1), p4: (-1, 1), uv1: (1, 0), uv2: (0, 1))

        super.init(frame: frame, device: composer.device)

        self.contentMode = .scaleAspectFill
        self.preferredFramesPerSecond = 30
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let t = CACurrentMediaTime()
        guard let texture = self.provider.provideTexture(renderer: self.composer, forHostTime: t) else {
            return
        }
        autoreleasepool {
            let commandBuffer = self.commandQueue.makeCommandBuffer()!
            if let renderPass = self.currentRenderPassDescriptor {
                let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)!
                encoder.setRenderPipelineState(self.pipelineState)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setVertexBuffer(self.quad, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
                encoder.endEncoding()
                commandBuffer.present(self.currentDrawable!)
            }
            commandBuffer.commit()
        }
    }

    // MARK: - Private

    private let commandQueue: MTLCommandQueue
    private let composer: Composer
    private let pipelineState: MTLRenderPipelineState
    private let provider: CameraTexture
    private let quad: MTLBuffer
    private let queue = DispatchQueue(label: "ReactionCam.CameraPreview")
}
