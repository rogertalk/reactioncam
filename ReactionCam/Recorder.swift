import AVFoundation
import UIKit

class Recorder: NSObject,
    AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureMetadataOutputObjectsDelegate
{
    enum Configuration {
        case audioOnly, backCamera, frontCamera
    }

    enum State: String {
        case idle, previewing, recording
    }

    static let instance = Recorder()

    /// Emitted for every frame that a face is detected.
    let faceDetected = Event<[AVMetadataFaceObject]>()

    /// Emitted whenever recording becomes unavailable to the app (e.g., background, split screen).
    let recorderUnavailable = Event<AVCaptureSession.InterruptionReason>()

    private(set) var audioLevel = Float(0)
    lazy var composer = Composer()

    var configuration = Configuration.frontCamera {
        didSet {
            self.queue.async {
                guard self.state != .idle else { return }
                self.configureDevice()
            }
        }
    }

    var currentZoom: CGFloat? {
        guard let camera = self.currentCamera?.device else {
            return nil
        }
        return camera.videoZoomFactor
    }

    var orientation: UIDeviceOrientation = .unknown {
        didSet {
            self.updateOrientation()
        }
    }

    private(set) var state = State.idle {
        didSet {
            Logging.debug("Recorder State", ["State": self.state.rawValue])
        }
    }

    /// An array of layers to draw into each video frame.
    /// The layer at index 0 is the back-most layer.
    var layers = [ComposerLayer]()

    override init() {
        // TODO: Consider exposing preview layer through a method instead.
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.capture)
        self.previewLayer.anchorPoint = .zero
        self.previewLayer.actions = ["bounds": NSNull()]
        self.previewLayer.backgroundColor = UIColor.black.cgColor
        self.previewLayer.masksToBounds = true
        self.previewLayer.videoGravity = .resizeAspectFill
        super.init()
        // Route the audio to the capture session.
        self.capture.usesApplicationAudioSession = true
        self.capture.automaticallyConfiguresApplicationAudioSession = false
        self.capture.addOutput(self.audioOutput)
        self.capture.addOutput(self.metadataOutput)
        self.capture.addOutput(self.videoOutput)
        self.audioOutput.setSampleBufferDelegate(self, queue: self.queue)
        self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: Int32(kCVPixelFormatType_32BGRA))]
        // Monitor interruptions to video capture.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(Recorder.captureSessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: nil)
        center.addObserver(self, selector: #selector(Recorder.captureSessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: nil)
        center.addObserver(self, selector: #selector(Recorder.captureSessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        self.writer?.cancel()
        // Ensure that we're not keeping a lock on the camera.
        self.configureDevice(camera: nil, microphone: .ignore)
    }

    /// Aborts a recording.
    func cancelRecording() {
        self.segments.removeAll()
        self.queue.async {
            self.state = .previewing
            guard self.state == .recording else {
                NSLog("%@", "WARNING: Attempted to cancel recording while not recording")
                return
            }
            guard let writer = self.writer else {
                preconditionFailure("there was no writer")
            }
            self.writer = nil
            writer.cancel()
            self.configureDevice()
        }
    }

    func finishRecording(callback: @escaping (AVURLAsset) -> Void) {
        guard self.state == .recording else {
            return
        }
        self.stopRecording() { asset in
            self.segments.append(asset)
            AssetEditor.merge(assets: self.segments) { result in
                self.segments.removeAll()
                callback(result ?? asset)
            }
        }
    }

    func focus(point: CGPoint) {
        self.queue.async {
            guard self.cameraLocked, let camera = self.currentCamera?.device else {
                return
            }
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = point
                camera.focusMode = .autoFocus
            }
            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = point
                camera.exposureMode = .continuousAutoExposure
            }
        }
    }

    func hookCameraOutput(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        self.videoOutput.setSampleBufferDelegate(delegate, queue: self.queue)
    }

    func hookCameraPreview() -> AVCaptureVideoPreviewLayer {
        self.previewLayer.removeFromSuperlayer()
        self.previewLayer.frame = .zero
        return self.previewLayer
    }

    func move(layer: ComposerLayer, above other: ComposerLayer) {
        self.move(layer: layer, toPositionOf: other, above: true)
    }

    func move(layer: ComposerLayer, below other: ComposerLayer) {
        self.move(layer: layer, toPositionOf: other, above: false)
    }

    /// Starts capturing input from the currently configured devices (but not writing).
    func startPreviewing() {
        self.queue.async {
            guard self.state == .idle else {
                NSLog("%@", "WARNING: Attempted to start previewing when not idle")
                return
            }
            self.state = .previewing
            self.configureDevice()
        }
    }

    /// Starts recording input to disk.
    func startRecording(quality: MediaWriterSettings.Quality) {
        guard let composer = self.composer, self.orientation != .unknown else {
            return
        }
        self.queue.async {
            guard self.state == .previewing else {
                NSLog("%@", "WARNING: Attempted to start recording when not previewing")
                return
            }
            self.state = .recording
            self.configureDevice()

            // Set up the recording destination.
            let writer = MediaWriter(
                url: URL.temporaryFileURL("mp4"),
                composer: composer,
                clock: self.capture.masterClock!,
                orientation: self.orientation,
                quality: quality)
            for layer in self.layers {
                writer.add(layer: layer)
            }
            self.writer = writer
            // Start writing.
            self.startTime = Date()
            if !writer.start() {
                NSLog("WARNING: Failed to start writing recording")
                self.cancelRecording()
            }
        }
    }

    /// Stops all capturing.
    func stopPreviewing() {
        self.queue.async {
            guard self.state == .previewing else {
                NSLog("%@", "WARNING: Attempted to stop previewing when not previewing")
                return
            }
            self.state = .idle
            self.configureDevice(camera: nil, microphone: .ignore)
            self.capture.stopRunning()
        }
    }

    func switchCamera() {
        self.queue.async {
            let useFront = self.configuration == .backCamera
            let newConfig: Configuration = useFront ? .frontCamera : .backCamera
            SettingsManager.preferFrontCamera = useFront

            if self.state == .recording {
                let quality = self.writer!.settings.quality
                self.stopRecording() { asset in
                    self.queue.async {
                        self.segments.append(asset)
                        self.configuration = newConfig
                        self.startRecording(quality: quality)
                    }
                }
            } else {
                self.configuration = newConfig
            }
        }
    }

    func toggleTorch(on: Bool) {
        self.queue.async {
            guard let device = self.currentCamera?.device else {
                return
            }
            if device.hasTorch {
                do {
                    try device.lockForConfiguration()
                    if on == true {
                        device.torchMode = .on
                    } else {
                        device.torchMode = .off
                    }
                    device.unlockForConfiguration()
                } catch {
                    print("Torch could not be used")
                }
            }
        }
    }

    func zoom(to factor: CGFloat) {
        guard let camera = self.currentCamera?.device else {
            return
        }
        camera.videoZoomFactor = max(1, min(factor, camera.activeFormat.videoMaxZoomFactor))
    }

    // MARK: - Private

    private let audioOutput = AVCaptureAudioDataOutput()
    private let capture = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "cam.reaction.ReactionCam.Recorder", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()

    private var addedAudio = false
    private var addedMetadata = false
    private var cameraLocked = false
    private var currentCamera: AVCaptureDeviceInput?
    private var segments = [AVURLAsset]()
    private var startTime = Date.distantFuture
    private var writer: MediaWriter?

    private lazy var audio: AVCaptureDeviceInput? = self.input(AVCaptureDevice.default(for: .audio))
    private lazy var back: AVCaptureDeviceInput? = self.input(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
    private lazy var front: AVCaptureDeviceInput? = self.input(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front))

    @objc private dynamic func captureSessionRuntimeError(notification: NSNotification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        Logging.danger("Recorder", [
            "Status": "Capture session runtime error",
            "Error": error?.localizedDescription ?? "N/A",
            "Reason": error?.localizedFailureReason ?? "N/A"])
    }

    @objc private dynamic func captureSessionWasInterrupted(notification: NSNotification) {
        guard
            let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
            let reason = AVCaptureSession.InterruptionReason(rawValue: rawReason)
            else
        {
            Logging.danger("Recorder", [
                "Status": "Capture session interrupted",
                "Error": "Failed to get reason"])
            NSLog("WARNING: Failed to get interruption reason (\(notification.userInfo ?? [:]))")
            return
        }
        Logging.warning("Recorder", [
            "Status": "Capture session interrupted",
            "Reason": reason.debugDescription])
        self.writer?.signalInterruption()
        self.recorderUnavailable.emit(reason)
    }

    @objc private dynamic func captureSessionInterruptionEnded(notification: NSNotification) {
        self.queue.async {
            guard self.state != .idle else { return }
            self.configureDevice()
        }
    }

    private func configureDevice() {
        let camera: AVCaptureDeviceInput?
        let mic: Microphone
        switch self.configuration {
        case .audioOnly:
            camera = nil
            mic = .bottom
        case .backCamera:
            camera = self.back
            mic = .front
        case .frontCamera:
            camera = self.front
            mic = .front
        }
        self.configureDevice(camera: camera, microphone: mic)
    }

    private func configureDevice(camera: AVCaptureDeviceInput?, microphone: Microphone) {
        self.capture.beginConfiguration()
        // Add audio when necessary, but only attempt it once.
        if !self.addedAudio {
            if let audio = self.audio, self.capture.canAddInput(audio) {
                self.capture.addInput(audio)
                self.addedAudio = true
            } else {
                NSLog("WARNING: Failed to add audio input")
            }
        }
        let cameraChanged = self.currentCamera !== camera
        // Stop capturing input from the previous camera if it changed.
        if cameraChanged, let input = self.currentCamera {
            self.capture.removeInput(input)
            if self.cameraLocked {
                input.device.unlockForConfiguration()
                self.cameraLocked = false
            }
        }
        self.currentCamera = camera
        if self.state != .recording {
            // Set up the audio route.
            AudioService.instance.microphone = microphone
        }
        // Configure the selected camera.
        guard let input = camera else {
            // There is no camera (audio only).
            self.capture.commitConfiguration()
            self.startCapture()
            return
        }
        if cameraChanged {
            // Lock the camera so we can update its properties.
            precondition(!self.cameraLocked, "camera shouldn't be locked")
            do {
                try input.device.lockForConfiguration()
                self.cameraLocked = true
                // Configure the camera for 30 FPS.
                input.device.activeVideoMinFrameDuration = CMTimeMake(1, 30)
                input.device.activeVideoMaxFrameDuration = CMTimeMake(1, 30)
            } catch {
                NSLog("%@", "WARNING: Failed to lock camera for configuration: \(error)")
            }
            // Set up data input.
            if self.capture.canAddInput(input) {
                self.capture.addInput(input)
            } else {
                NSLog("WARNING: Failed to set up camera")
            }
        }
        // Disable continuous autofocus while recording.
        if self.cameraLocked && input.device.isFocusModeSupported(.continuousAutoFocus) {
            input.device.focusMode = self.state == .recording ? .locked : .continuousAutoFocus
        }
        input.device.setExposureTargetBias(0.4, completionHandler: nil)
        self.capture.commitConfiguration()
        if !self.addedMetadata {
            if self.metadataOutput.availableMetadataObjectTypes.contains(.face) {
                self.addedMetadata = true
                self.metadataOutput.metadataObjectTypes = [.face]
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.queue)
            }
        }
        self.startCapture()
        self.updateOrientation()
    }

    private func input(_ device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let device = device else { return nil }
        return try? AVCaptureDeviceInput(device: device)
    }

    private func move(layer: ComposerLayer, toPositionOf other: ComposerLayer, above: Bool) {
        self.queue.async {
            self.writer?.move(layer: layer, toPositionOf: other, above: true)
            // Replicate the move in the layers list.
            var ao, bo: Int?
            for (i, l) in self.layers.enumerated() {
                if l === layer { ao = i }
                if l === other { bo = above ? i + 1 : i }
            }
            guard let a = ao, let b = bo, a != b else { return }
            self.layers.insert(layer, at: b)
            self.layers.remove(at: a < b ? a : a + 1)
        }
    }

    private func startCapture() {
        guard self.state != .idle else {
            return
        }
        if !self.capture.isRunning {
            self.capture.startRunning()
        }
        if !self.capture.isRunning {
            NSLog("%@", "WARNING: Failed to start capture session (\(self.capture.isInterrupted ? "interrupted" : "not interrupted"))")
        }
    }

    /// Stops recording input and calls the callback when done writing to disk.
    private func stopRecording(callback: @escaping (AVURLAsset) -> Void) {
        self.queue.async {
            guard self.state == .recording else {
                NSLog("%@", "WARNING: Attempted to stop recording when not recording")
                return
            }
            self.state = .previewing
            guard let writer = self.writer else {
                preconditionFailure("there was no writer")
            }
            self.writer = nil
            // Create a recording which holds all the relevant information for the recorded media.
            writer.finish {
                callback(AVURLAsset(url: writer.url))
            }
            self.configureDevice()
        }
    }

    private func updateAudioLevel(sampleBuffer: CMSampleBuffer) {
        var buffer: CMBlockBuffer? = nil

        // Needs to be initialized somehow, even if we take only the address.
        var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            nil,
            &audioBufferList,
            MemoryLayout<AudioBufferList>.size,
            nil,
            nil,
            UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            &buffer)

        guard let audioBuffer = UnsafeMutableAudioBufferListPointer(&audioBufferList).first else {
            return
        }

        let samples = UnsafeMutableBufferPointer<Int16>(
            start: audioBuffer.mData?.assumingMemoryBound(to: Int16.self),
            count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size)

        guard samples.count > 0 else {
            return
        }

        self.audioLevel = sqrtf(samples.reduce(0) { $0 + powf(Float($1), 2) } / Float(samples.count))
    }

    private func updateOrientation() {
        guard let connection = self.videoOutput.connection(with: .video) else {
            return
        }
        let newOrientation: AVCaptureVideoOrientation
        switch self.orientation {
        case .landscapeLeft:
            newOrientation = .landscapeRight
        case .landscapeRight:
            newOrientation = .landscapeLeft
        case .portrait:
            newOrientation = .portrait
        case .portraitUpsideDown:
            newOrientation = .portraitUpsideDown
        default:
            return
        }
        self.queue.async {
            connection.videoOrientation = newOrientation
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        switch captureOutput {
        case self.audioOutput:
            // TODO: Enable this if we want to monitor audio level while recording.
            //self.updateAudioLevel(sampleBuffer: sampleBuffer)
            self.writer?.append(audio: sampleBuffer)
        default:
            preconditionFailure("unknown capture output: \(captureOutput)")
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let faces = metadataObjects.compactMap({ $0 as? AVMetadataFaceObject })
        self.faceDetected.emit(faces)
    }
}
