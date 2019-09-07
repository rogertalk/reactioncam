import MediaPlayer

class VolumeMonitor: NSObject {
    static let instance = VolumeMonitor()

    let routeChange = Event<Float>()
    let volumeChange = Event<Float>()

    var active = false {
        didSet {
            guard oldValue != self.active else {
                return
            }
            if self.active {
                self.start()
            } else {
                self.stop()
            }
        }
    }

    private(set) var volume = Float(0)

    override init() {
        super.init()
    }

    deinit {
        self.stop()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume" else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.handleVolumeChange()
        }
    }

    // MARK: - Private

    private let volumeView = MPVolumeView(frame: CGRect(x: 0, y: -100, width: 0, height: 0))

    private var emittingVolumeEvents = false

    @objc private dynamic func audioSessionRouteChange(notification: NSNotification) {
        guard let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            return
        }

        let current = AVAudioSession.sharedInstance().currentRoute
        guard
            current.outputs.count >= 1,
            previous.outputs.count == 0 || current.outputs[0].uid != previous.outputs[0].uid
            else { return }
        // Temporarily ignore events after a route change.
        self.emittingVolumeEvents = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.emittingVolumeEvents = true
        }
        // Cap the new volume slider so we can keep getting events.
        self.capVolume()
        // Emit a separate event since there won't be a volume event.
        self.routeChange.emit(self.getSlider()?.value ?? 0)
    }

    @discardableResult
    private func capVolume() -> Bool {
        guard let slider = self.getSlider() else {
            return false
        }
        // Force slider to remain slightly above/below the min/max values.
        if slider.value > 0.999 {
            slider.value = 0.999
        } else if slider.value < 0.001 {
            slider.value = 0.001
        } else {
            return false
        }
        return true
    }

    private func getSlider() -> UISlider? {
        return self.volumeView.subviews.compactMap({ $0 as? UISlider }).first
    }

    private func handleVolumeChange() {
        guard self.emittingVolumeEvents, let slider = self.getSlider() else {
            return
        }
        if self.capVolume() {
            // If the volume was capped we can expect a second event.
            return
        }
        self.volume = slider.value
        self.volumeChange.emit(slider.value)
    }

    private func start() {
        self.emittingVolumeEvents = false
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(VolumeMonitor.audioSessionRouteChange), name: .AVAudioSessionRouteChange, object: nil)
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: [], context: nil)
        DispatchQueue.main.async {
            self.volumeView.alpha = 0.0001
            self.volumeView.isUserInteractionEnabled = false
            self.volumeView.showsRouteButton = false
            self.volumeView.setVolumeThumbImage(UIImage(), for: .normal)
            UIApplication.shared.keyWindow!.addSubview(self.volumeView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Cap the volume 100 ms later to avoid native volume UI showing up.
            self.capVolume()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Start emitting events after 200 ms since the first few events are fickle.
            self.emittingVolumeEvents = true
        }
    }

    private func stop() {
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume", context: nil)
        DispatchQueue.main.async {
            self.volumeView.removeFromSuperview()
        }
    }
}
