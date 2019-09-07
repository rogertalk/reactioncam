import Alamofire
import AlamofireImage
import AVFoundation
import Foundation

class CacheService {
    typealias CacheCallback = (Error?) -> ()
    typealias ThumbnailCallback = (UIImage?) -> ()

    static let instance = CacheService()

    var hasPendingDownloads: Bool {
        return self.pendingDownloads.count > 0
    }

    var urlCached = Event<URL>()

    /// Converts a potentially remote URL to what it should be for the cache.
    func getLocalURL(_ url: URL) -> URL {
        if url.scheme == "file" {
            // Don't relocate local files.
            return url
        }
        return self.cacheDirectoryURL.appendingPathComponent(url.lastPathComponent)
    }

    /// Returns `true` if the URL exists cached locally on disk; otherwise, `false`.
    func hasCached(url: URL) -> Bool {
        return !self.isDownloading(url: url) && FileManager.default.fileExists(atPath: self.getLocalURL(url).path)
    }

    /// Returns `true` if the URL is in the process of being downloaded; otherwise, `false`.
    func isDownloading(url: URL) -> Bool {
        var downloading = false
        self.queue.sync {
            downloading = self.pendingDownloads[url] != nil
        }
        return downloading
    }

    // MARK: - Private

    private let autoCacheMaxAge = TimeInterval(24 * 3600)
    private let cacheDirectoryURL: URL
    private let cacheLifetime = TimeInterval(7 * 86400)
    private let queue = DispatchQueue(label: "cam.reaction.ReactionCam.CacheService", qos: .userInitiated)
    private let thumbnailCache = AutoPurgingImageCache()

    private var pendingDownloads = [URL: [CacheCallback]]()
    private var pendingThumbnails = [URL: [ThumbnailCallback]]()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectoryURL = caches.appendingPathComponent("MediaCache")

        // Ensure that the cache directory exists.
        let fs = FileManager.default
        if !fs.fileExists(atPath: self.cacheDirectoryURL.path) {
            try! fs.createDirectory(at: self.cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        // Kick off a background worker to prune the caches directory of stale files.
        DispatchQueue.global(qos: .background).async {
            self.pruneDirectory(url: self.cacheDirectoryURL)
            self.pruneDirectory(url: URL(fileURLWithPath: NSTemporaryDirectory()))
        }
    }

    private func cache(remoteURL url: URL, callback: CacheCallback? = nil) {
        // Don't "download" from the file system and avoid duplicate downloads.
        guard !self.hasCached(url: url) && !url.isFileURL else {
            callback?(nil)
            return
        }
        self.queue.async {
            if self.pendingDownloads[url] != nil {
                if let callback = callback {
                    self.pendingDownloads[url]!.append(callback)
                }
                return
            } else {
                self.pendingDownloads[url] = callback != nil ? [callback!] : []
            }
            self.log("Downloading \(url)")
            // Start a download which will move the file to the cache directory when done.
            // TODO: Verify that Alamofire uses background transfer.
            let request = Alamofire.download(url, method: .get, parameters: nil, encoding: URLEncoding.default, headers: nil, to: {
                (_, _) -> (URL, DownloadRequest.DownloadOptions) in
                // Return the path on disk where the file should be stored.
                return (self.getLocalURL(url), [])
            })
            let start = Date().timeIntervalSince1970
            request.response(completionHandler: { response in
                self.queue.async {
                    let callbacks = self.pendingDownloads.removeValue(forKey: url)
                    callbacks?.forEach { cb in
                        DispatchQueue.main.async { cb(response.error) }
                    }
                    let duration = Date().timeIntervalSince1970 - start
                    if let error = response.error {
                        self.log("Download failed: \(error) (\(url))")
                        Logging.warning("Caching Failed", ["RequestDuration": duration])
                    } else {
                        self.log("Download completed: \(url)")
                        self.urlCached.emit(url)
                        var params: [String: Any] = ["RequestDuration": duration]
                        if let size = self.getLocalURL(url).fileSize {
                            params["AverageBytesPerSec"] = Double(size) / duration
                            params["FileSizeMB"] = Double(size) / 1024 / 1024
                        }
                        Logging.debug("Caching Completed", params)
                    }
                }
            })
        }
    }

    private func log(_ message: String) {
        NSLog("[CacheService] %@", message)
    }

    private func pruneDirectory(url: URL) {
        let fs = FileManager.default
        do {
            for entry in try fs.contentsOfDirectory(atPath: url.path) {
                let path = url.appendingPathComponent(entry).path
                guard let created = try? fs.attributesOfItem(atPath: path)[.creationDate] as! Date else {
                    continue
                }
                // TODO: Consider recurring files that should not be pruned.
                if Date().timeIntervalSince(created) > self.cacheLifetime {
                    self.log("Pruning: \(path) (\(created))")
                    try fs.removeItem(atPath: path)
                }
            }
        } catch {
            self.log("Failed to prune directory: \(error)")
        }
    }
}
