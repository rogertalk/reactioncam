import AVFoundation
import UIKit

class MediaWriter {
    let settings: MediaWriterSettings

    /// The local file URL that the video will be written to.
    var url: URL {
        return self.asset.outputURL
    }

    init(url: URL, composer: Composer, clock: CMClock, orientation: UIDeviceOrientation, quality: MediaWriterSettings.Quality = .medium) {
        self.clock = clock

        switch orientation {
        case .landscapeLeft, .landscapeRight:
            self.settings = MediaWriterSettings(quality: quality, orientation: .landscape)
        default:
            self.settings = MediaWriterSettings(quality: quality, orientation: .portrait)
        }

        self.asset = try! AVAssetWriter(url: url, fileType: .mp4)
        self.asset.shouldOptimizeForNetworkUse = true

        self.audio = AVAssetWriterInput(mediaType: .audio, outputSettings: self.settings.audioSettings)
        self.audio.expectsMediaDataInRealTime = true
        self.asset.add(self.audio)

        self.video = AVAssetWriterInput(mediaType: .video, outputSettings: self.settings.videoSettings)
        self.video.expectsMediaDataInRealTime = true
        self.asset.add(self.video)

        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: NSNumber(value: true),
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: Int32(kCVPixelFormatType_32BGRA)),
            kCVPixelBufferWidthKey as String: self.settings.width,
            kCVPixelBufferHeightKey as String: self.settings.height,
            ]
        self.adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.video, sourcePixelBufferAttributes: attributes)
        self.composerWorker = composer.makeWorker(size: CGSize(width: self.settings.width, height: self.settings.height))
    }

    func add(layer: ComposerLayer) {
        self.queue.sync {
            self.composerWorker.add(layer: layer)
        }
    }

    func append(audio sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        self.queue.async {
            if !self.writerSessionStarted {
                // Wait for video before writing any audio (because audio may arrive much sooner than video).
                return
            }
            guard self.canAppend, self.audio.isReadyForMoreMediaData else {
                return
            }
            self.audio.append(sampleBuffer)
        }
    }

    func cancel() {
        self.queue.async {
            if let displayLink = self.displayLink {
                displayLink.invalidate()
                self.displayLink = nil
            }
            self.canAppend = false
            // TODO: Delete temporary file.
            self.asset.cancelWriting()
        }
    }

    func finish(callback: @escaping () -> ()) {
        // Clean up and complete writing.
        self.queue.async {
            if let displayLink = self.displayLink {
                displayLink.invalidate()
                self.displayLink = nil
            }
            self.canAppend = false
            self.audio.markAsFinished()
            self.video.markAsFinished()
            self.asset.finishWriting {
                if self.asset.status != .completed {
                    Logging.danger("Media Writer", [
                        "Status": "Finished with error",
                        "Error": self.asset.error?.localizedDescription ?? "N/A",
                        "Code": self.asset.status.rawValue])
                }
                // Let the UI know as soon as the file is ready.
                callback()
            }
        }
    }

    func move(layer: ComposerLayer, toPositionOf other: ComposerLayer, above: Bool = false) {
        self.queue.async {
            self.composerWorker.move(layer: layer, toPositionOf: other, above: above)
        }
    }

    func signalInterruption() {
        self.queue.async {
            guard self.writerSessionStarted else {
                return
            }
            self.writerSessionInterrupted = true
        }
    }

    func start() -> Bool {
        // TODO: Make result a callback.
        var result = false
        self.queue.sync {
            result = self.asset.startWriting()
            self.canAppend = true
            let displayLink = CADisplayLink(target: self, selector: #selector(MediaWriter.renderVideoFrame))
            displayLink.preferredFramesPerSecond = 30
            self.displayLink = displayLink
            self.queue.async {
                guard let displayLink = self.displayLink else {
                    return
                }
                self.composerWorker.prepare {
                    displayLink.add(to: .main, forMode: .commonModes)
                }
            }
        }
        return result
    }

    // MARK: - Private

    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let asset: AVAssetWriter
    private let audio, video: AVAssetWriterInput
    private let clock: CMClock
    private let composerWorker: Composer.Worker
    private let minDelta = CMTime(value: 15000000, timescale: 1000000000)
    private let queue = DispatchQueue(label: "cam.reaction.ReactionCam.MediaWriter." + UUID().uuidString,
                                      qos: .userInteractive)
    private let semaphore = DispatchSemaphore(value: 1)

    private var canAppend = false
    private var displayLink: CADisplayLink?
    private var lastVideoTimestamp = CMTime(value: 0, timescale: 1)
    private var writerSessionInterrupted = false
    private var writerSessionStarted = false

    private func createPixelBuffer() -> CVPixelBuffer? {
        guard let pool = self.adaptor.pixelBufferPool else {
            return nil
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    private func ensureSessionStarted(buffer sampleBuffer: CMSampleBuffer) {
        self.ensureSessionStarted(time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    private func ensureSessionStarted(time: CMTime) {
        guard !self.writerSessionStarted else {
            return
        }
        self.asset.startSession(atSourceTime: time)
        self.writerSessionInterrupted = false
        self.writerSessionStarted = true
    }

    @objc private dynamic func renderVideoFrame() {
        guard self.semaphore.wait(timeout: .now()) == .success else {
            NSLog("%@", "WARNING: Dropped a video frame due to previous frame still rendering")
            return
        }
        self.queue.async {
            defer { self.semaphore.signal() }
            guard self.video.isReadyForMoreMediaData else {
                return
            }
            guard let link = self.displayLink else {
                return
            }
            let timestamp = CMClockGetTime(self.clock)
            guard let buffer = self.createPixelBuffer() else {
                NSLog("%@", "WARNING: Failed to create pixel buffer from pool")
                return
            }
            guard self.composerWorker.notifyIntentToWrite() else {
                return
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let data = CVPixelBufferGetBaseAddress(buffer) else {
                CVPixelBufferUnlockBaseAddress(buffer, [])
                return
            }
            self.composerWorker.writeTexture(into: data, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
            // Start rendering textures for next frame.
            self.composerWorker.startComposing(forHostTime: link.timestamp + link.duration)
            // Append the buffer data to the writer.
            self.safelyAppendVideo(buffer, timestamp: timestamp)
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }
    }

    @discardableResult
    private func safelyAppendVideo(_ buffer: CVPixelBuffer, timestamp: CMTime) -> Bool {
        guard self.canAppend else {
            return false
        }
        guard timestamp - self.minDelta > self.lastVideoTimestamp else {
            NSLog("%@", "WARNING: Dropped a video frame due to negative/low time delta")
            return false
        }
        self.ensureSessionStarted(time: timestamp)
        guard !self.writerSessionInterrupted else {
            return false
        }
        if !self.adaptor.append(buffer, withPresentationTime: timestamp) {
            // TODO: Check the asset writer status and notify if it failed.
            NSLog("%@", "WARNING: Failed to append a frame to pixel buffer adaptor")
            return false
        }
        self.lastVideoTimestamp = timestamp
        return true
    }
}
