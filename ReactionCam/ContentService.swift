import AVFoundation
import FBSDKShareKit
import Foundation
import TMTumblrSDK
import TwitterKit

class ContentService {
    static let instance = ContentService()

    let contentCreated = Event<Content>()
    let contentUpdated = Event<Content>()
    let featuredContentChanged = Event<Void>()
    let recentContentChanged = Event<Void>()
    let serviceConnected = Event2<String, Int>() // Service id and status code.
    let subscriptionContentChanged = Event<Void>()
    let trendingContentChanged = Event<Void>()

    private(set) var featuredContent: [Content] = [] {
        didSet {
            if self.featuredContent.count > 0 {
                self.featuredContentTimestamp = Date()
            }
            self.featuredContentChanged.emit()
        }
    }

    private(set) var hasLoadedRecents = false
    private(set) var hasLoadedSubscriptionContent = false
    
    private(set) var recentContent: [Content] = [] {
        didSet {
            self.recentContentChanged.emit()
        }
    }

    private(set) var subscriptionContent: [Content] = [] {
        didSet {
            self.subscriptionContentChanged.emit()
        }
    }

    private(set) var trendingContent: [Content] = [] {
        didSet {
            self.trendingContentChanged.emit()
        }
    }

    func contentRef(from job: CompletedUploadJob) -> ContentRef? {
        return self.contentRef(from: job.metadata)
    }

    func contentRef(from job: UploadJob) -> ContentRef? {
        return self.contentRef(from: job.metadata)
    }

    func exchangeCode(service: String, authCode: String?) {
        guard let authCode = authCode else {
            self.serviceConnected.emit(service, -1)
            return
        }
        switch service {
        case "youtube":
            Intent.authYouTube(code: authCode).performWithoutDispatch(BackendClient.api) {
                SettingsManager.autopostYouTube = $0.successful && $0.code == 200
                self.serviceConnected.emit(service, $0.code)
            }
        default:
            self.serviceConnected.emit(service, -1)
        }
    }

    func loadFeaturedContent() {
        // Only pull #featured automatically every 10 minutes.
        if let timestamp = self.featuredContentTimestamp, timestamp.timeIntervalSinceNow > -600 {
            return
        }
        self.getContentList(tags: ["featured"], sortBy: "recent", limit: 5, cursor: nil) { result, _ in
            guard let result = result else {
                return
            }
            self.featuredContent = result
        }
    }

    func loadRecentContent(refresh: Bool = true, callback: ((Bool) -> ())? = nil) {
        guard refresh || self.recentCursor != nil else {
            // There is no more content to load
            callback?(true)
            return
        }
        self.getContentList(tags: ["reaction"], sortBy: "recent", limit: 15, cursor: refresh ? nil : self.recentCursor) {
            self.hasLoadedRecents = true
            guard let result = $0 else {
                callback?(false)
                return
            }
            if refresh {
                self.recentContent = result
            } else {
                self.recentContent.append(contentsOf: result)
            }
            self.recentCursor = $1
            callback?(true)
        }
    }

    func loadTrendingContent() {
        self.getContentList(tags: ["trending"]) { result, _ in
            guard let result = result else {
                return
            }
            self.trendingContent = result
        }
    }

    func loadSubscriptionContent() {
        guard BackendClient.api.session != nil else {
            assertionFailure("Don't call loadSubscriptionContent() without a session")
            return
        }
        // TODO: Cursor support.
        Intent.getOwnFollowingContentList(tag: "reaction", cursor: nil).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data, let list = data["data"] as? [DataType] else {
                return
            }
            self.subscriptionContent = list.compactMap(Content.init)
            self.hasLoadedSubscriptionContent = true
        }
    }
    
    func removeSubscriptionContent(id: Int64) {
        guard let index = self.subscriptionContent.index(where: { $0.id == id }) else {
            return
        }
        self.subscriptionContent.remove(at: index)
    }
    
    func getContent(id: Int64, callback: @escaping (Content?) -> ()) {
        Intent.getContent(id: id).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data, let content = Content(data: data) else {
                callback(nil)
                return
            }
            callback(content)
        }
    }

    func getContent(slug: String, callback: @escaping (Content?) -> ()) {
        Intent.getContentBySlug(slug: slug).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data, let content = Content(data: data) else {
                callback(nil)
                return
            }
            callback(content)
        }
    }

    func getContentList(tags: [String], sortBy: String? = nil, limit: Int? = nil, cursor: String? = nil, callback: @escaping ([Content]?, String?) -> ()) {
        Intent.getContentList(tags: tags, sortBy: sortBy, limit: limit, cursor: cursor).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data, let list = data["data"] as? [DataType] else {
                callback(nil, nil)
                return
            }
            let cursor = data["cursor"] as? String
            callback(list.compactMap(Content.init), cursor)
        }
    }

    func getPublicRequestList(tags: [String], sortBy: String? = nil, limit: Int? = nil, cursor: String? = nil, callback: @escaping ([PublicContentRequest]?, String?) -> ()) {
        Intent.getPublicContentRequestList(tags: tags, sortBy: sortBy, limit: limit, cursor: cursor).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data, let list = data["data"] as? [DataType] else {
                callback(nil, nil)
                return
            }
            let cursor = data["cursor"] as? String
            callback(list.compactMap(PublicContentRequest.init), cursor)
        }
    }

    func getRelatedContentList(for content: ContentInfo, sortBy: String? = nil, cursor: String? = nil, callback: @escaping ([Content]?, String?) -> ()) {
        Intent.getRelatedContentList(contentId: content.id, tag: "reaction", sortBy: sortBy, limit: 20, cursor: cursor).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data, let list = data["data"] as? [DataType] else {
                callback(nil, nil)
                return
            }
            let cursor = data["cursor"] as? String
            // Inject related info.
            let related: [Content] = list.compactMap {
                guard let item = Content(data: $0) else {
                    return nil
                }
                item.relatedTo = content
                return item
            }
            callback(related, cursor)
        }
    }

    func getUserContentList(for id: Int64, tag: String, cursor: String? = nil, callback: @escaping ([Content], String?) -> ()) {
        let intent: Intent
        if id == BackendClient.api.session?.id {
            intent = Intent.getOwnContentList(tag: tag, limit: 20, cursor: cursor)
        } else {
            intent = Intent.getProfileContentList(identifier: id.description, tag: tag, limit: 20, cursor: cursor)
        }
        intent.perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [[String: Any]] else {
                callback([], cursor)
                return
            }
            let cursor = $0.data?["cursor"] as? String
            callback(data.compactMap(Content.init(data:)), cursor)
        }
    }

    func getYouTubeVideos(callback: @escaping ([YouTubeVideo]) -> ()) {
        Intent.getYouTubeVideos(limit: nil).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                callback([])
                return
            }
            callback(data.compactMap(YouTubeVideo.init(data:)))
        }
    }

    func postToFacebook(content: ContentInfo, caption: String? = nil) {
        guard let url = content.webURL else {
            return
        }
        let fbContent = FBSDKShareLinkContent()
        fbContent.contentURL = url
        fbContent.hashtag = FBSDKHashtag(string: "#reactioncam")
        let api = FBSDKShareAPI()
        api.shareContent = fbContent
        if let caption = caption {
            api.message = caption
        }
        api.share()
        Logging.log("Post To Service", ["Service": "Facebook"])
    }

    func postToTwitter(content: ContentInfo) {
        guard let url = content.webURL, let id = TWTRTwitter.sharedInstance().sessionStore.session()?.userID else {
            return
        }

        let titleLength = 140 - url.absoluteString.count - 1

        var message = ""
        if let title = content.title {
            message = title.hasPrefix("@") ? ".\(title.prefix(titleLength - 1))" : String(title.prefix(titleLength))
        }
        message.append(" \(url.absoluteString)")

        let client = TWTRAPIClient(userID: id)
        let statusesShowEndpoint = "https://api.twitter.com/1.1/statuses/update.json"
        let params = ["status": message]
        var clientError : NSError?

        let request = client.urlRequest(withMethod: "POST", urlString: statusesShowEndpoint, parameters: params, error: &clientError)

        Logging.log("Post To Service", ["Service": "Twitter"])
        client.sendTwitterRequest(request) { (response, data, error) in
            if let error = error {
                Logging.danger("Autopost Twitter Failed", ["Error": error.localizedDescription])
            }
        }
    }

    func postToTumblr(content: ContentInfo) {
        guard let url = content.webURL, let client = TMAPIClient.sharedInstance() else {
            return
        }
        client.userInfo { data, error in
            guard error == nil,
                let data = data as? DataType,
                let user = data["user"] as? DataType,
                let blogs = user["blogs"] as? [DataType],
                let primaryBlog = blogs.first(where: { $0["primary"] as? Bool == true }),
                let blogName = primaryBlog["name"] as? String
                else { return }
            var tags = [String]()
            var description = ""
            if let title = content.title {
                let words = title.components(separatedBy: " ")
                tags = words.filter({ $0.hasPrefix("#") })
                description = words.filter({ !$0.hasPrefix("#") }).joined(separator: " ")
            }
            tags.append("reactioncam")
            let params = ["description": description,
                          "tags": tags.joined(separator: ","),
                          "url": url.absoluteString]
            client.link(blogName, parameters: params) { _, error in
                if let error = error {
                    Logging.danger("Autopost Tumblr Failed", ["Error": error.localizedDescription])
                }
            }
            Logging.log("Post To Service", ["Service": "Tumblr"])
        }
    }

    func reportView(id: Int64) {
        let (notViewed, _) = self.viewedContentIds.insert(id)
        guard notViewed else { return }
        Intent.viewContent(contentId: id).perform(BackendClient.api)
    }

    func search(query: String, callback: @escaping ([ContentResult]) -> ()) {
        Intent.searchContent(query: query).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                callback([])
                return
            }
            callback(data.map(ContentResult.init(data:)))
        }
    }

    func submitPublicRequestEntry(_ requestId: Int64, contentId: Int64?, source: String, callback: ((Bool, String?) -> ())? = nil) {
        Intent.submitPublicContentRequestEntry(requestId: requestId, contentId: contentId).perform(BackendClient.api) {
            guard $0.successful else {
                Logging.warning("Content Service", [
                    "Status": "Error submitting entry to public content request",
                    "Code": String($0.code),
                    "Id": contentId.flatMap(String.init) ?? "N/A",
                    "RequestId": String(requestId),
                    "Source": source])
                callback?(false, ($0.data?["error"] as? DataType)?["message"] as? String)
                return
            }
            Logging.debug("Content Service", [
                "Status": "Submitted entry to public content request",
                "Id": contentId.flatMap(String.init) ?? "N/A",
                "RequestId": String(requestId),
                "Source": source])
            callback?(true, nil)
        }
    }

    func submitPublicRequestEntry(_ requestId: Int64, youTubeId: String, source: String, callback: ((Bool, String?) -> ())? = nil) {
        Intent.submitPublicContentRequestEntryFromYouTube(requestId: requestId, videoId: youTubeId).perform(BackendClient.api) {
            guard $0.successful else {
                Logging.warning("Content Service", [
                    "Status": "Error submitting entry to public content request (YouTube)",
                    "Code": String($0.code),
                    "Id": youTubeId,
                    "RequestId": String(requestId),
                    "Source": source])
                callback?(false, ($0.data?["error"] as? DataType)?["message"] as? String)
                return
            }
            Logging.debug("Content Service", [
                "Status": "Submitted entry to public content request (YouTube)",
                "Id": youTubeId,
                "RequestId": String(requestId),
                "Source": source])
            callback?(true, nil)
        }
    }

    func update(pending: PendingContent, for jobId: String, callback: @escaping (Content?) -> ()) {
        guard let promise = self.contentFromJobId[jobId] else {
            Logging.danger("Content Service", [
                "Status": "Failed to get content from job id when updating metadata",
                "JobId": jobId])
            callback(nil)
            return
        }
        let newTags = pending.tags
        var metadata: [String: Any] = [
            "facebook": pending.postToFacebook,
            "facebook_caption": pending.facebookCaption ?? NSNull(),
            "tags": newTags,
            "title": pending.title ?? NSNull(),
            "tumblr": pending.postToTumblr,
            "twitter": pending.postToTwitter,
            "youtube": pending.postToYouTube,
        ]
        if let url = pending.thumbnailURL, let bookmark = try? url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) {
            metadata["image_bookmark"] = bookmark.base64EncodedString()
        }
        if let request = pending.request {
            metadata["request_id"] = request.id
        }
        if UploadService.instance.setMetadata(metadata, for: jobId) {
            Logging.debug("Content Service", [
                "Status": "Updated in progress upload job metadata",
                "JobId": jobId,
                "Tags": newTags.joined(separator: ", ")])
            // The job is still in progress and its metadata has been updated.
            // The upload completion handler will take care of the logic instead.
            promise.then(callback, { _ in callback(nil) })
            return
        }
        // Since the upload is completed, this promise should resolve almost immediately.
        promise.then({ content in
            // Update the content with all the metadata from the pending content object.
            var thumbnail: Intent.Image? = nil
            if let url = pending.thumbnailURL, let data = try? Data(contentsOf: url) {
                thumbnail = .jpeg(data)
            }
            Logging.debug("Content Service", [
                "Status": "Updating finished upload job metadata (content)",
                "Id": String(content.id),
                "JobId": jobId,
                "Tags": newTags.joined(separator: ", ")])
            Intent.updateContent(contentId: content.id, tags: newTags, title: pending.title, thumbnail: thumbnail).perform(BackendClient.api) {
                if let url = pending.thumbnailURL, FileManager.default.fileExists(atPath: url.path) {
                    _ = try? FileManager.default.removeItem(at: url)
                }
                guard $0.successful, let data = $0.data, let content = Content(data: data) else {
                    // TODO: We need to ensure that content is always made public.
                    Logging.warning("Content Service", [
                        "Status": "Failed to update content",
                        "Code": String($0.code),
                        "JobId": jobId])
                    callback(nil)
                    return
                }
                if let request = pending.request {
                    self.submitPublicRequestEntry(request.id, contentId: content.id, source: "Update Content")
                }
                if pending.postToFacebook {
                    self.postToFacebook(content: content, caption: pending.facebookCaption)
                }
                if pending.postToTumblr {
                    self.postToTumblr(content: content)
                }
                if pending.postToTwitter {
                    self.postToTwitter(content: content)
                }
                if pending.postToYouTube {
                    self.uploadToYouTube(id: content.id)
                }
                Logging.debug("Content Service", [
                    "Status": "Made content public after creation",
                    "Id": String(content.id),
                    "JobId": jobId])
                Logging.success("Content Made Public", [
                    "AfterCreation": true,
                    "Destinations": pending.extraMetadata["destinations"] ?? "Unknown",
                    "Orientation": "Unknown",  // TODO: Make this information available somehow.
                    "Source": pending.extraMetadata["source"] ?? "Unknown"])
                callback(content)
            }
        }) {
            // Error handler for promise.
            Logging.warning("Content Service", [
                "Status": "Could not get content from job",
                "Error": $0.localizedDescription,
                "JobId": jobId])
            callback(nil)
        }
    }

    @discardableResult
    func upload(recording: AVURLAsset, tags: [String], title: String?, thumbnailURL: URL?, relatedContent: ContentRef?, requestId: Int64?, extraMetadata: [String: Any] = [:]) throws -> UploadJob {
        let dimensions: Any
        if let size = recording.tracks(withMediaType: .video).first?.naturalSize {
            dimensions = ["width": size.width, "height": size.height]
        } else {
            dimensions = NSNull()
        }
        var metadata = [
            "dedupe": UUID().uuidString,
            "dimensions": dimensions,
            "duration": Int(recording.duration.seconds * 1000),
            "original": relatedContent?.toDict() ?? NSNull(),
            "tags": tags,
            "title": title ?? NSNull(),
        ]
        if let url = thumbnailURL, let bookmark = try? url.bookmarkData() {
            metadata["image_bookmark"] = bookmark.base64EncodedString()
        }
        if let requestId = requestId {
            metadata["request_id"] = requestId
        }
        metadata.merge(extraMetadata) { (a, _) in return a }
        let job = try UploadService.instance.upload(file: recording.url, metadata: metadata)
        let (p, resolve, reject) = Promise<Content>.exposed()
        self.callbacks[job.id] = (resolve, reject)
        self.contentFromJobId[job.id] = p
        return job
    }

    func uploadToYouTube(id: Int64) {
        Intent.uploadToYouTube(contentId: id).perform(BackendClient.api)
        Logging.log("Post To Service", ["Service": "YouTube"])
    }

    // MARK: - Private

    private var callbacks = [String: ((Content) -> (), (Error) -> ())]()
    private var contentFromJobId = [String: Promise<Content>]()
    private var deduped = Set<String>()
    private var featuredContentTimestamp: Date?
    private var recentCursor: String?
    private var viewedContentIds = Set<Int64>()

    private init() {
        UploadService.instance.uploadCompleted.addListener(self, method: ContentService.handleUploadCompleted)
        UploadService.instance.startReporting()
    }

    private func contentRef(from metadata: [String: Any]) -> ContentRef? {
        if let id = metadata["original_id"] as? Int64 {
            return .id(id)
        } else if let dict = metadata["original"] as? [String: Any] {
            return ContentRef.fromDict(dict)
        } else if let url = (metadata["original_url"] as? String).flatMap({ URL(string: $0) }) {
            return .url(url)
        }
        return nil
    }

    private func handleUploadCompleted(job: CompletedUploadJob) {
        guard let duration = job.metadata["duration"] as? Int else {
            return
        }
        let dedupe = job.metadata["dedupe"] as? String
        if let dedupe = dedupe {
            guard !self.deduped.contains(dedupe) else {
                Logging.warning("Content Service", [
                    "Status": "Ignoring duplicate upload completion",
                    "JobId": job.id])
                return
            }
            self.deduped.insert(dedupe)
        }
        let dimensions: CGSize?
        if let data = job.metadata["dimensions"] as? DataType {
            dimensions = CGSize(width: data["width"] as! CGFloat, height: data["height"] as! CGFloat)
        } else {
            dimensions = nil
        }
        let tags = (job.metadata["tags"] as? [String]) ?? ["recording"]
        let title = job.metadata["title"] as? String
        var thumbnail: Intent.Image? = nil
        var thumbnailURL: URL? = nil
        if let bookmarkString = job.metadata["image_bookmark"] as? String,
            let bookmark = Data(base64Encoded: bookmarkString) {
            var isStale = false
            if let resolve = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale), let url = resolve, let imageData = try? Data(contentsOf: url) {
                thumbnailURL = url
                thumbnail = .jpeg(imageData)
            }
        }
        let uploadToYouTube = (job.metadata["youtube"] as? Bool) ?? false
        let intent = Intent.createContent(url: job.token.publicURL,
                                          duration: duration,
                                          tags: tags,
                                          title: title,
                                          thumbnail: thumbnail,
                                          dimensions: dimensions,
                                          relatedContent: self.contentRef(from: job),
                                          dedupe: dedupe,
                                          uploadToYouTube: uploadToYouTube)
        intent.performWithBackgroundTask(BackendClient.api) {
            if let url = thumbnailURL, FileManager.default.fileExists(atPath: url.path) {
                _ = try? FileManager.default.removeItem(at: url)
            }
            let content: Content?
            let contentId: Int64?
            if $0.successful, let data = $0.data, let c = Content(data: data) {
                UploadService.instance.finish(jobId: job.id)
                content = c
                contentId = c.id
                // Post to third-party networks from the client.
                if let post = job.metadata["facebook"] as? Bool, post {
                    self.postToFacebook(content: c, caption: job.metadata["facebook_caption"] as? String)
                }
                if let post = job.metadata["tumblr"] as? Bool, post {
                    self.postToTumblr(content: c)
                }
                if let post = job.metadata["twitter"] as? Bool, post {
                    self.postToTwitter(content: c)
                }
                if !uploadToYouTube, let post = job.metadata["youtube"] as? Bool, post {
                    // This should be a very rare case, but handle it just in case.
                    self.uploadToYouTube(id: c.id)
                    Logging.danger("Content Service", [
                        "Status": "Rare Event! (Contact Blixt)",
                        "JobId": job.id])
                }
                // TODO: Don't use hardcoded tags here.
                if c.tags.contains("reaction") {
                    if let requestId = job.metadata["request_id"] as? Int64 {
                        self.submitPublicRequestEntry(requestId, contentId: c.id, source: "Create Content")
                    }
                    Logging.debug("Content Service", [
                        "Status": "Created public content",
                        "Id": String(c.id),
                        "JobId": job.id])
                    self.recentContent.insert(c, at: 0)
                    Logging.success("Content Made Public", [
                        "AfterCreation": false,
                        "Destinations": job.metadata["destinations"] ?? "Unknown",
                        "Orientation": dimensions?.orientationDescription ?? "Unknown",
                        "Source": job.metadata["source"] ?? "Unknown"])
                } else {
                    Logging.debug("Content Service", [
                        "Status": "Created recording (not yet public)",
                        "Id": String(c.id),
                        "JobId": job.id])
                }
                self.contentCreated.emit(c)
                self.contentUpdated.emit(c)
            } else if $0.code == 409 {
                // The content was created previously but we didn't hear about it.
                UploadService.instance.finish(jobId: job.id)
                content = nil
                if let data = $0.data, let id = data["content_id"] as? Int64 {
                    Logging.debug("Content Service", [
                        "Status": "Ignoring duplicate content creation (backend 409)",
                        "Id": String(id),
                        "JobId": job.id])
                    contentId = id
                } else {
                    Logging.warning("Content Service", [
                        "Status": "Could not get content id from duplicate error response",
                        "JobId": job.id])
                    contentId = nil
                }
            } else {
                Logging.warning("Content Service", [
                    "Status": "Content creation failed",
                    "Code": String($0.code),
                    "JobId": job.id])
                if let dedupe = dedupe {
                    // Don't consider this a dupe since it failed.
                    self.deduped.remove(dedupe)
                }
                content = nil
                contentId = nil
            }
            guard let (resolve, reject) = self.callbacks.removeValue(forKey: job.id) else {
                // The app has probably been exited since this job was started.
                return
            }
            if let content = content {
                resolve(content)
            } else if let id = contentId {
                Intent.getContent(id: id).perform(BackendClient.api) {
                    guard $0.successful, let data = $0.data, let content = Content(data: data) else {
                        Logging.warning("Content Service", [
                            "Status": "Could not get original content by id after duplicate error",
                            "Code": String($0.code),
                            "JobId": job.id])
                        reject($0.error ?? NSError(domain: "cam.reaction", code: -1, userInfo: nil))
                        return
                    }
                    resolve(content)
                }
            } else {
                reject($0.error ?? NSError(domain: "cam.reaction", code: -1, userInfo: nil))
            }
        }
    }
}
