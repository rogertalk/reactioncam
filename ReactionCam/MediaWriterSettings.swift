import AVFoundation
import UIKit

struct MediaWriterSettings {
    enum Quality: String {
        case medium, high

        var presetName: String {
            switch self {
            case .medium:
                return AVAssetExportPreset1280x720
            case .high:
                return AVAssetExportPreset1920x1080
            }
        }
    }

    enum Orientation {
        case landscape, portrait, square
    }
    
    let quality: Quality
    let orientation: Orientation
    let width, height: Int

    init(quality: Quality, orientation: Orientation) {
        self.quality = quality
        self.orientation = orientation
        let size = MediaWriterSettings.size(quality: quality, orientation: orientation)
        self.width = Int(size.width)
        self.height = Int(size.height)
    }

    var audioSettings: [String: Any] {
        let bitRate, sampleRate: Int
        switch self.quality {
        case .medium, .high:
            bitRate = 64000
            sampleRate = 44100
        }
        return [
            AVNumberOfChannelsKey: NSNumber(value: 1),
            AVEncoderBitRatePerChannelKey: NSNumber(value: bitRate),
            AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
            AVSampleRateKey: NSNumber(value: sampleRate),
        ]
    }

    var videoSettings: [String: Any] {
        let bitRate: Int
        switch self.quality {
        case .medium:
            bitRate = 1572864 // TODO: May need to bump this to 2097152.
        case .high:
            bitRate = 2621440
        }
        return [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoCompressionPropertiesKey: [
                AVVideoAllowFrameReorderingKey: NSNumber(value: true),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High41,
                AVVideoMaxKeyFrameIntervalDurationKey: NSNumber(value: 1),
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoExpectedSourceFrameRateKey: NSNumber(value: 30),
                AVVideoAverageBitRateKey: NSNumber(value: bitRate),
                "Priority": NSNumber(value: 80),
                "RealTime": NSNumber(value: true),
            ],
            AVVideoWidthKey: NSNumber(value: self.width),
            AVVideoHeightKey: NSNumber(value: self.height),
        ]
    }

    static func size(quality: Quality, orientation: Orientation) -> CGSize {
        let long, short: Int
        switch quality {
        case .medium:
            long = 1280
            short = 720
        case .high:
            long = 1920
            short = 1080
        }
        switch orientation {
        case .landscape:
            return CGSize(width: long, height: short)
        case .portrait:
            return CGSize(width: short, height: long)
        case .square:
            return CGSize(width: short, height: short)
        }
    }

    static func size(quality: Quality, orientation: UIDeviceOrientation) -> CGSize {
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            return self.size(quality: quality, orientation: Orientation.landscape)
        default:
            return self.size(quality: quality, orientation: Orientation.portrait)
        }
    }
}
