import AVFoundation

class AudioLevelMeter {
    private(set) static var audioLevel = Float(0)

    init() {
        self.setupAudioProcessingTap()
    }

    func getTappedPlayerItem(url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        if let tap = self.tap, let track = item.asset.tracks(withMediaType: .audio).first {
            let inputParams = AVMutableAudioMixInputParameters(track: track)
            inputParams.audioTapProcessor = tap.takeUnretainedValue()
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [inputParams]
            item.audioMix = audioMix
        }
        return item
    }

    private var tap: Unmanaged<MTAudioProcessingTap>?
    private var tapProcessCallback: MTAudioProcessingTapProcessCallback = {
        (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        var status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        guard status == noErr, let audioBuffer = UnsafeMutableAudioBufferListPointer(bufferListInOut).first else {
            NSLog("%@", "WARNING: MTAudioTap processing failed with status \(status).")
            return
        }
        let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
        let samples = UnsafeMutableBufferPointer<Float>(
            start: audioBuffer.mData?.assumingMemoryBound(to: Float.self),
            count: sampleCount)
        guard samples.count > 0 else {
            return
        }
        AudioLevelMeter.audioLevel = sqrtf(samples.reduce(0) { $0 + powf($1, 2) } / Float(sampleCount))
    }

    private func setupAudioProcessingTap() {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: nil,
            finalize: nil,
            prepare: nil,
            unprepare: nil,
            process: self.tapProcessCallback)
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &self.tap)
        if status != noErr {
            NSLog("%@", "WARNING: Failed to set up audio tap, got status \(status).")
        }
    }
}
