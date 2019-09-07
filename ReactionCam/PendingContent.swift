import AVFoundation
import Foundation
import UIKit

class PendingContent {
    enum ContentType {
        case recording(isVlog: Bool)
        case repost(ContentInfo)
        case upload
    }

    var assets: [AVURLAsset] {
        didSet {
            self.ensureMutable()
            self.cancelUpload()
            self.mergedAsset = self.assets.count == 1 ? self.assets.first : nil
            self.isSaved = false
        }
    }

    var duration: TimeInterval {
        if let asset = self.mergedAsset {
            return asset.duration.seconds
        }
        return self.assets.reduce(0, { $0 + $1.duration.seconds })
    }

    var extraMetadata = [String: Any]() { didSet { self.ensureMutable() } }
    var facebookCaption: String? { didSet { self.ensureMutable() } }
    private(set) var isSaved: Bool = false
    private(set) var mergedAsset: AVURLAsset?
    private(set) var persisted: Content?
    var postToFacebook = false { didSet { self.ensureMutable() } }
    var postToTumblr = false { didSet { self.ensureMutable() } }
    var postToTwitter = false { didSet { self.ensureMutable() } }
    var postToYouTube = false { didSet { self.ensureMutable() } }
    var related: RelatedContentEntry? { didSet { self.ensureMutable() } }
    var request: PublicContentRequest? { didSet { self.ensureMutable() } }
    var type: ContentType = .recording(isVlog: false) { didSet { self.ensureMutable() } }
    private(set) var uploadJobId: String?

    var tags: [String] {
        var tags = Set(["reaction"])
        if let title = self.title {
            tags.formUnion(title.matches(of: "#(\\w+)").compactMap({ $0.groups[1]?.lowercased() }))
        }
        tags.remove("repost")
        switch self.type {
        case let .recording(isVlog):
            if isVlog {
                tags.insert("vlog")
            }
        case .repost:
            tags.insert("repost")
        default:
            break
        }
        return Array(tags)
    }

    var thumbnailURL: URL? { didSet { self.ensureMutable() } }
    var title: String? { didSet { self.ensureMutable() } }

    deinit {
        pthread_mutex_destroy(&self.mutex)
    }

    init(assets: [AVURLAsset] = []) {
        pthread_mutex_init(&self.mutex, nil)
        self.assets = assets
        if assets.count == 1 {
            self.mergedAsset = assets.first
        }
        UploadService.instance.uploadStarted.addListener(self, method: PendingContent.handleUploadStarted)
    }

    func create() -> Promise<URL> {
        pthread_mutex_lock(&self.mutex)
        do {
            let (jobId, promise) = try self.ensureUploadStarted()
            self.isCommitted = true
            pthread_mutex_unlock(&self.mutex)
            // Make the content public.
            ContentService.instance.update(pending: self, for: jobId) {
                guard let content = $0 else {
                    return
                }
                pthread_mutex_lock(&self.mutex)
                self.persisted = content
                pthread_mutex_unlock(&self.mutex)
            }
            return promise
        } catch {
            pthread_mutex_unlock(&self.mutex)
            Logging.danger("Pending Content", [
                "Status": "Failed to start upload",
                "Error": error.localizedDescription])
            return .reject(error)
        }
    }

    func discard() {
        pthread_mutex_lock(&self.mutex)
        self.isCommitted = false
        let assets = self.assets
        pthread_mutex_unlock(&self.mutex)
        self.assets = []
        assets.forEach { asset in
            do {
                try FileManager.default.removeItem(at: asset.url)
            } catch {
                Logging.warning("Pending Content", [
                    "Status": "Could not delete an asset",
                    "Error": error.localizedDescription])
            }
        }
    }

    // TODO: Make this private once it's no longer used in CreationViewController.
    func merge(completion: @escaping (AVURLAsset?) -> ()) {
        guard self.assets.count > 0 else {
            completion(nil)
            return
        }
        if let asset = self.mergedAsset {
            completion(asset)
            return
        }
        AssetEditor.merge(assets: self.assets) { [weak self] in
            guard let content = self else {
                completion(nil)
                return
            }
            guard let asset = $0 else {
                Logging.danger("Pending Content", ["Status": "Could not merge assets"])
                let alert = AnywhereAlertController(title: "Oops! 😅", message: "Could not create video. Make sure you have enough space on your \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") and try again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in
                    completion(nil)
                })
                alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in
                    content.merge(completion: completion)
                })
                alert.show()
                return
            }
            content.mergedAsset = asset
            completion(asset)
        }
    }

    func save(source: String, completion: ((String?) -> ())? = nil) {
        self.merge {
            guard let asset = $0 else {
                completion?(nil)
                return
            }
            MediaManager.save(asset: asset, source: source, completion: completion)
            self.isSaved = true
        }
    }

    func upload() {
        pthread_mutex_lock(&self.mutex)
        defer { pthread_mutex_unlock(&self.mutex) }
        do {
            try self.ensureUploadStarted()
        } catch {
            Logging.warning("Pending Content", [
                "Status": "Failed to pre-start upload",
                "Error": error.localizedDescription])
        }
    }

    // MARK: - Private

    private var isCommitted = false
    private var mutex = pthread_mutex_t()
    private var urlCallbacks: ((URL) -> (), (Error) -> ())?
    private var urlPromise: Promise<URL>?

    private func cancelUpload() {
        pthread_mutex_lock(&self.mutex)
        guard let jobId = self.uploadJobId, !self.isCommitted else {
            pthread_mutex_unlock(&self.mutex)
            return
        }
        let cbs = self.urlCallbacks
        self.uploadJobId = nil
        self.urlCallbacks = nil
        self.urlPromise = nil
        pthread_mutex_unlock(&self.mutex)
        UploadService.instance.cancel(jobId: jobId)
        if let (_, reject) = cbs {
            reject(PendingContentError.uploadCancelled)
        }
    }

    @discardableResult
    private func ensureMutable() -> Bool {
        pthread_mutex_lock(&self.mutex)
        defer { pthread_mutex_unlock(&self.mutex) }
        guard !self.isCommitted else {
            assertionFailure("Cannot modify content after create() has been called")
            return false
        }
        return true
    }

    /// Ensures that the latest assets are being uploaded. Cancels previous upload if newer assets are available.
    ///
    /// IMPORTANT: Must be called while mutex is locked!
    @discardableResult
    private func ensureUploadStarted() throws -> (String, Promise<URL>) {
        if let jobId = self.uploadJobId, let promise = self.urlPromise {
            return (jobId, promise)
        }
        guard let asset = self.mergedAsset else {
            throw PendingContentError.assetsMustBeMerged
        }
        // TODO: Upload with tag "is draft" instead of "recording".
        let job = try ContentService.instance.upload(
            recording: asset,
            tags: ["recording"],
            title: self.title,
            thumbnailURL: self.thumbnailURL,
            relatedContent: self.related?.mappedRef,
            requestId: self.request?.id,
            extraMetadata: self.extraMetadata)
        self.uploadJobId = job.id
        let (p, s, e) = Promise<URL>.exposed()
        self.urlCallbacks = (s, e)
        self.urlPromise = p
        // TODO: Settle Promise with actual URL.
        DispatchQueue.main.async {
            s(URL(string: "about:blank")!)
        }
        return (job.id, p)
    }

    private func handleUploadStarted(job: UploadJob, token: UploadToken) {
        pthread_mutex_lock(&self.mutex)
        guard
            let id = self.uploadJobId,
            job.id == id,
            let url = URL(string: "https://www.reaction.cam/v/\(token.id)"),
            let (success, _) = self.urlCallbacks
            else
        {
            pthread_mutex_unlock(&self.mutex)
            return
        }
        pthread_mutex_unlock(&self.mutex)
        success(url)
    }
}
