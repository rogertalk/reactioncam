import AVFoundation
import SDAVAssetExportSession

class AssetEditor {
    static func trim(asset: AVURLAsset, to segments: [(CMTime, CMTime)], completion: @escaping (AVURLAsset?) -> ()) {
        guard asset.url.isFileURL,
            let assetVideoTrack = asset.tracks(withMediaType: .video).first,
            let assetAudioTrack = asset.tracks(withMediaType: .audio).first
            else {
                Logging.danger("Trim Asset", [
                    "Result": "Failed",
                    "Error": "Could not get audio/video tracks"])
                return
        }

        let composition = AVMutableComposition()
        guard
            let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: CMPersistentTrackID()),
            let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: CMPersistentTrackID())
            else
        {
            Logging.danger("Trim Asset", ["Error": "Could not add audio/video track"])
            return
        }

        // Delete everything except the specified segments.
        for (start, end) in segments {
            let difference = CMTimeSubtract(end, start)
            guard difference.isValid && difference.seconds > 0 else {
                continue
            }
            let range = CMTimeRangeMake(start, difference)
            do {
                let duration = composition.duration
                // Append the specified slice of the video to the composition.
                try video.insertTimeRange(range, of: assetVideoTrack, at: duration)
                try audio.insertTimeRange(range, of: assetAudioTrack, at: duration)
            } catch let e {
                let error = "Failed to insert time range: \(e)"
                NSLog(error)
                Logging.warning("Trim Asset", [
                    "Start": range.start.seconds,
                    "Duration": range.duration,
                    "Error": error])
                continue
            }
        }

        let destination = URL.temporaryFileURL("mp4")
        let preset: String
        if #available(iOS 11.0, *) {
            preset = AVAssetExportPresetHighestQuality
        } else {
            preset = AVAssetExportPresetPassthrough
        }
        guard self.clearDestination(url: destination),
            let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
                Logging.danger("Trim Asset", [
                    "Result": "Failed",
                    "Error": "Could not create export session"])
                completion(nil)
                return
        }
        exportSession.outputURL = destination
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        if FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.removeItem(at: destination)
            } catch let e {
                let error = "Could not clear export destination: \(e)"
                NSLog(error)
                Logging.danger("Trim Asset", [
                    "Result": "Failed",
                    "Error": error])
                completion(nil)
                return
            }
        }

        self.setIdleTimerStatus(isDisabled: true)
        exportSession.exportAsynchronously {
            self.setIdleTimerStatus(isDisabled: false)
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    Logging.debug("Trim Asset", ["Result": "Success"])
                    completion(AVURLAsset(url: destination))
                case .failed:
                    Logging.danger("Trim Asset", [
                        "Result": "Failed",
                        "Error": exportSession.error?.localizedDescription ?? "Error while exporting"])
                    completion(nil)
                default:
                    completion(nil)
                }
            }
        }
    }
    
    static func merge(assets: [AVURLAsset], completion: @escaping (AVURLAsset?) -> ()) {
        // Nothing to merge
        guard assets.count > 1 else {
            completion(assets.first)
            return
        }

        let composition = AVMutableComposition()
        guard
            let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: CMPersistentTrackID()),
            let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: CMPersistentTrackID())
            else
        {
            Logging.danger("Merge Assets", ["Result": "Failed", "Error": "Could not add audio/video track"])
            return
        }
        assets.forEach { asset in
            guard
                asset.url.isFileURL,
                let assetVideoTrack = asset.tracks(withMediaType: .video).first
                else
            {
                Logging.danger("Merge Assets", ["Result": "Failed", "Error": "Could not get video track"])
                completion(nil)
                return
            }
            do {
                // Append the specified slice of the video to the composition.
                let startTime = composition.duration
                try video.insertTimeRange(assetVideoTrack.timeRange, of: assetVideoTrack, at: startTime)
                if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                    let range = CMTimeRangeMake(assetAudioTrack.timeRange.start, assetVideoTrack.timeRange.duration)
                    try audio.insertTimeRange(range, of: assetAudioTrack, at: startTime)
                }
            } catch let e {
                let error = "Error during composition: \(e)"
                NSLog(error)
                Logging.danger("Merge Assets", ["Result": "Failed", "Error": error])
                completion(nil)
            }
        }

        let destination = URL.temporaryFileURL("mp4")
        guard self.clearDestination(url: destination),
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                Logging.danger("Merge Assets", ["Result": "Failed", "Error": "Could not create export session"])
                completion(nil)
                return
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        self.setIdleTimerStatus(isDisabled: true)
        exportSession.exportAsynchronously {
            self.setIdleTimerStatus(isDisabled: false)
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    Logging.debug("Merge Assets", ["Result": "Success"])
                    completion(AVURLAsset(url: destination))
                case .failed:
                    Logging.danger("Merge Assets", [
                        "Result": "Failed",
                        "Error": exportSession.error?.localizedDescription ?? "Error while exporting"])
                    completion(nil)
                default:
                    completion(nil)
                }
            }
        }
    }

    static func sanitize(asset: AVURLAsset, completion: @escaping (AVURLAsset?) -> ()) {
        guard asset.url.isFileURL,
            let assetVideoTrack = asset.tracks(withMediaType: .video).first else {
                Logging.danger("Sanitize Asset", ["Result": "Failed", "Error": "Could not get video track"])
                completion(nil)
                return
        }

        let composition = AVMutableComposition()
        guard
            let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else
        {
            Logging.danger("Sanitize Asset", ["Error": "Could not add audio/video track"])
            return
        }
        do {
            // Append the specified slice of the video to the composition.
            try video.insertTimeRange(assetVideoTrack.timeRange, of: assetVideoTrack, at: kCMTimeZero)
            // Add the same time range as asset video track
            if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                try audio.insertTimeRange(assetVideoTrack.timeRange, of: assetAudioTrack, at: kCMTimeZero)
            }
        } catch let e {
            let error = "Failed to insert time range: \(e)"
            NSLog(error)
            Logging.warning("Sanitize Asset", ["Error": error])
            completion(nil)
            return
        }

        let destination = URL.temporaryFileURL("mp4")
        guard self.clearDestination(url: destination),
            let encoder = SDAVAssetExportSession(asset: composition) else {
                Logging.warning("Sanitize Asset", ["Error": "Could not create export session"])
                completion(nil)
                return
        }

        let t = assetVideoTrack.preferredTransform
        let hasTransform = t != .identity
        let isPortraitTransform = t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0

        // Portrait videos recorded on iPhone are stored as landscape with a transform to display vertically
        // Only account for this if necessary, as it results in slower cropping
        if hasTransform {
            let videoComp = AVMutableVideoComposition()
            let videoSize = assetVideoTrack.naturalSize
            videoComp.renderSize = isPortraitTransform ? CGSize(width: videoSize.height, height: videoSize.width) : videoSize
            videoComp.frameDuration = CMTimeMake(1, 30)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRangeMake(kCMTimeZero, composition.duration)
            let layerInstruction = self.videoCompositionInstruction(track: composition.tracks(withMediaType: .video)[0], assetTrack: assetVideoTrack)
            instruction.layerInstructions = [layerInstruction]
            videoComp.instructions = [instruction]
            encoder.videoComposition = videoComp
        }

        let size = assetVideoTrack.naturalSize
        let orientation: MediaWriterSettings.Orientation
        if abs(size.width - size.height) < 5 {
            orientation = .square
        } else if size.isLandscape && !isPortraitTransform {
            orientation = .landscape
        } else {
            orientation = .portrait
        }
        let writerSettings = MediaWriterSettings(quality: .medium, orientation: orientation)
        encoder.videoSettings = writerSettings.videoSettings
        encoder.videoSettings[AVVideoScalingModeKey] = AVVideoScalingModeResizeAspect
        encoder.audioSettings = writerSettings.audioSettings
        encoder.outputFileType = AVFileType.mp4.rawValue
        encoder.outputURL = destination
        self.setIdleTimerStatus(isDisabled: true)
        encoder.exportAsynchronously {
            DispatchQueue.main.async {
                self.setIdleTimerStatus(isDisabled: false)
                switch encoder.status {
                case .completed:
                    Logging.debug("Sanitize Asset", ["Result": "Success"])
                    completion(AVURLAsset(url: destination))
                case .failed:
                    Logging.danger("Sanitize Asset", [
                        "Result": "Failed",
                        "Error": encoder.error?.localizedDescription ?? "Error while exporting"])
                    completion(nil)
                default:
                    completion(nil)
                }
            }
        }
    }

    private static func videoCompositionInstruction(track: AVCompositionTrack, assetTrack: AVAssetTrack) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let transform = assetTrack.preferredTransform
        let assetInfo = self.orientation(from: transform)

        // TODO: Use this to scale videos that do not have the same aspect ratio
        let scaleToFitRatio: CGFloat = track.naturalSize.width / assetTrack.naturalSize.width
        let scaleFactor = CGAffineTransform(scaleX: scaleToFitRatio, y: scaleToFitRatio)

        if assetInfo.isPortrait {
            instruction.setTransform(assetTrack.preferredTransform.concatenating(scaleFactor), at: kCMTimeZero)
        } else {
            var concat = assetTrack.preferredTransform.concatenating(scaleFactor).concatenating(CGAffineTransform(translationX: 0, y: assetTrack.naturalSize.width / 2))
            if assetInfo.orientation == .down {
                let fixUpsideDown = CGAffineTransform(rotationAngle: CGFloat(Float.pi))
                let centerFix = CGAffineTransform(translationX: assetTrack.naturalSize.width, y: assetTrack.naturalSize.height)
                concat = fixUpsideDown.concatenating(centerFix).concatenating(scaleFactor)
            }
            instruction.setTransform(concat, at: kCMTimeZero)
        }
        return instruction
    }

    private static func orientation(from transform: CGAffineTransform) -> (orientation: UIImageOrientation, isPortrait: Bool) {
        var assetOrientation = UIImageOrientation.up
        var isPortrait = false
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            assetOrientation = .right
            isPortrait = true
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            assetOrientation = .left
            isPortrait = true
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            assetOrientation = .up
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            assetOrientation = .down
        }
        return (assetOrientation, isPortrait)
    }

    private static func clearDestination(url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return true
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let e {
            let error = "Could not clear export destination: \(e)"
            Logging.log("Video Editor", [
                "Action": "Clear Destination",
                "Result": "Failed",
                "Error": error])
            return false
        }
        return true
    }
    
    private static func setIdleTimerStatus(isDisabled: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = isDisabled
        }
    }
}
