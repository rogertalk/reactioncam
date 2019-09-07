import AVFoundation
import Foundation
import Photos

class MediaManager {
    static let photoAlbumName = "REACTION.CAM"

    static func save(asset: AVURLAsset, source: String, completion: ((String?) -> ())? = nil) {
        let previousStatus = PHPhotoLibrary.authorizationStatus()
        PHPhotoLibrary.requestAuthorization { status in
            if previousStatus == .notDetermined {
                if status == .authorized {
                    Logging.success("Permission Granted", ["Permission": "Photo Library"])
                } else {
                    Logging.danger("Permission Denied", ["Permission": "Photo Library"])
                }
            }
            guard status == .authorized else {
                let alert = AnywhereAlertController(title: "Allow saving photos", message: "You must first grant permission to save photos to the Camera Roll.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    UIApplication.shared.open(
                        URL(string: UIApplicationOpenSettingsURLString)!,
                        options: [:],
                        completionHandler: nil)
                })
                alert.show()
                return
            }

            var assetLocalId: String? = nil
            self.fetchAssetCollection() { assetCollection in
                PHPhotoLibrary.shared().performChanges({
                    let assetChangeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: asset.url)
                    assetLocalId = assetChangeRequest?.placeholderForCreatedAsset?.localIdentifier
                    if let album = assetCollection {
                        let assetPlaceHolder = assetChangeRequest?.placeholderForCreatedAsset
                        let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                        let enumeration: NSArray = [assetPlaceHolder!]
                        albumChangeRequest?.addAssets(enumeration)
                    }
                }) { success, error in
                    DispatchQueue.main.async {
                        guard success else {
                            Logging.danger("Media Manager Error", ["Error": error?.localizedDescription ?? "Unknown"])
                            let alert = AnywhereAlertController(title: "Uh-oh!", message: "We failed to save the video 😧\nTry freeing up some space!", preferredStyle: .alert)
                            alert.addCancel(title: "OK") {
                                completion?(nil)
                            }
                            alert.show()
                            return
                        }
                        var params: [String: Any] = ["Duration": asset.duration.seconds]
                        if let size = asset.url.fileSize {
                            params["FileSizeMB"] = Double(size) / 1024 / 1024
                        }
                        Logging.log("Recording Saved", params)
                        completion?(assetLocalId)
                    }
                }
            }
        }
    }

    private static func fetchAssetCollection(callback: @escaping (PHAssetCollection?) -> ()) {
        let getCollection: () -> PHAssetCollection? = {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", self.photoAlbumName)
            return PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .any,
                options: fetchOptions).firstObject
        }

        if let assetCollection = getCollection() {
            callback(assetCollection)
            return
        }
        // Create it if it doesn't already exist
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: MediaManager.photoAlbumName)
        }) { success, _ in
            callback(getCollection())
        }
    }
}
