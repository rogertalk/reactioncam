import AVFoundation

class AudioService {
    static let instance = AudioService()

    /// The microphone to use. Note that an external microphone will take precedence.
    var microphone = Microphone.ignore {
        didSet {
            guard oldValue != self.microphone else {
                return
            }
            self.updateRoutes()
        }
    }

    var isHeadphonesConnected: Bool {
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            $0.portType == AVAudioSessionPortHeadphones
        }
    }

    var isLoudspeaker: Bool {
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            $0.portType == AVAudioSessionPortBuiltInSpeaker
        }
    }

    func updateRoutes() {
        self.queue.async {
            let audio = AVAudioSession.sharedInstance()
            do {
                if audio.category != AVAudioSessionCategoryPlayAndRecord {
                    try audio.setCategory(AVAudioSessionCategoryPlayAndRecord,
                                          mode: AVAudioSessionModeDefault,
                                          options: [.defaultToSpeaker, .allowBluetooth])
                }
                try audio.setActive(true)
            } catch {
                NSLog("%@", "WARNING: Failed to update audio session: \(error)")
            }

            // Update the microphone orientation.
            let usingInternalMic = AVAudioSession.sharedInstance().currentRoute.inputs.contains {
                $0.portType == AVAudioSessionPortBuiltInMic
            }
            if
                usingInternalMic,
                let orientation = self.microphone.orientation,
                let sources = audio.inputDataSources,
                let mic = sources.first(where: {
                    if let o = $0.orientation {
                        return o == orientation
                    } else {
                        return false
                    }
                }),
                audio.inputDataSource != mic
            {
                do {
                    try audio.setInputDataSource(mic)
                    print("Switched to internal microphone \(orientation)")
                } catch {
                    NSLog("%@", "WARNING: Failed to use \(orientation) microphone: \(error)")
                }
            }
        }
    }

    // MARK: - Private

    private let queue = DispatchQueue(label: "cam.reaction.ReactionCam.AudioService")

    private init() {
        // Monitor changes to audio session.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(AudioService.audioSessionInterruption), name: .AVAudioSessionInterruption, object: nil)
        center.addObserver(self, selector: #selector(AudioService.audioSessionMediaServicesWereReset), name: .AVAudioSessionMediaServicesWereReset, object: nil)
        center.addObserver(self, selector: #selector(AudioService.audioSessionRouteChange), name: .AVAudioSessionRouteChange, object: nil)
    }

    @objc private dynamic func audioSessionInterruption(notification: NSNotification) {
        let info = notification.userInfo!
        let type = AVAudioSessionInterruptionType(rawValue: info[AVAudioSessionInterruptionTypeKey] as! UInt)!
        switch type {
        case .began:
            Logging.warning("Audio Interrupt")
        case .ended:
            let options = AVAudioSessionInterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as! UInt)
            Logging.debug("Audio Interrupt Ended", ["ShouldResume": options.contains(.shouldResume)])
            self.updateRoutes()
        }
    }

    @objc private dynamic func audioSessionRouteChange(notification: NSNotification) {
        let info = notification.userInfo!
        let reason = AVAudioSessionRouteChangeReason(rawValue: info[AVAudioSessionRouteChangeReasonKey] as! UInt)!
        let new = AVAudioSession.sharedInstance().currentRoute
        let old = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        // updateRoutes() overrides the output route and sets category, causing an infinite call loop.
        guard reason != .override && reason != .categoryChange, new != old else {
            return
        }
        self.updateRoutes()
    }

    @objc private dynamic func audioSessionMediaServicesWereReset(notification: NSNotification) {
        Logging.warning("Audio Media Services Reset")
    }
}
