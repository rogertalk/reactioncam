import AVFoundation

enum Microphone {
    case back, bottom, front, ignore

    var orientation: String? {
        switch self {
        case .back:
            return AVAudioSessionOrientationBack
        case .bottom:
            return AVAudioSessionOrientationBottom
        case .front:
            return AVAudioSessionOrientationFront
        case .ignore:
            return nil
        }
    }
}
