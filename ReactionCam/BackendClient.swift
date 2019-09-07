import Alamofire
import Foundation
import UIKit

typealias DataType = [String: Any]
typealias IntentCallback = (IntentResult) -> Void

/// The result from performing an intent.
struct IntentResult {
    let data: DataType?
    let error: Error?
    let code: Int

    init(data: DataType?, error: Error?, code: Int = -1) {
        self.data = data
        self.error = error
        self.code = code
    }

    var successful: Bool {
        return self.error == nil
    }
}

/// Anything that takes an intent, performs it, and returns the result in the provided callback.
protocol Performer {
    func performIntent(_ intent: Intent, callback: IntentCallback?)
}

extension ContentRef {
    func setUpRequest(_ info: inout RequestInfo, prefix: String = "content") {
        switch self {
        case let .id(id):
            info.queryString["\(prefix)_id"] = String(id)
        case let .metadata(creator, url, duration, title, videoURL, thumbURL):
            info.form["\(prefix)_creator_identifier"] = creator
            info.form["\(prefix)_url"] = url.absoluteString
            info.form["\(prefix)_duration"] = String(duration)
            info.form["\(prefix)_title"] = title
            info.form["\(prefix)_video_url"] = videoURL?.absoluteString
            info.form["\(prefix)_thumb_url"] = thumbURL?.absoluteString
        case let .url(url):
            info.form["\(prefix)_url"] = url.absoluteString
        }
    }
}

/// Allows performing a request with a performer as a method on the intent.
extension Intent {
    func perform(_ performer: Performer, callback: IntentCallback? = nil) {
        performer.performIntent(self) { result in
            guard let callback = callback else {
                return
            }
            DispatchQueue.main.async {
                callback(result)
            }
        }
    }

    func performWithBackgroundTask(_ performer: Performer, callback: IntentCallback? = nil) {
        var taskId = UIBackgroundTaskInvalid
        taskId = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            if taskId != UIBackgroundTaskInvalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = UIBackgroundTaskInvalid
            }
        })
        performer.performIntent(self) { result in
            callback?(result)
            if taskId != UIBackgroundTaskInvalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = UIBackgroundTaskInvalid
            }
        }
    }

    func performWithoutDispatch(_ performer: Performer, callback: @escaping IntentCallback) {
        performer.performIntent(self, callback: callback)
    }
}

/// A complete implementation of a performer (for making HTTP calls to the backend).
class BackendClient: Performer {
    static let api = BackendClient("https://api.reaction.cam", id: "API", version: 55)
    static let upload = BackendClient("https://upload.reaction.cam", id: "UploadService", version: 2)

    let backgroundManager: Alamofire.SessionManager
    let baseURL: URL
    let version: Int

    var session: Session? {
        didSet {
            if let old = oldValue, old.id != self.session?.id {
                Session.clear()
                SettingsManager.resetUser()
                self.loggedOut.emit()
            }
            if let session = self.session {
                do {
                    try session.save()
                } catch {
                    NSLog("%@", "WARNING: Failed to save session")
                }
                if session.id != oldValue?.id {
                    self.loggedIn.emit(session)
                }
            }
            self.sessionChanged.emit()
        }
    }

    let loggedIn = Event<Session>()
    let loggedOut = Event<Void>()
    let sessionChanged = Event<Void>()

    init(_ baseURLString: String, id: String, version: Int) {
        self.baseURL = URL(string: baseURLString)!
        self.version = version
        self.session = Session.load()
        self.retryRequestQueue = [Intent]()
        self.manager = Alamofire.SessionManager()
        self.backgroundManager = Alamofire.SessionManager(
            configuration: .background(withIdentifier: "cam.reaction.ReactionCam.BackgroundManager.\(id)"))
    }

    /// Gets the necessary information for being able to perform a request.
    func getRequestInfo(_ intent: Intent) -> RequestInfo? {
        var info = RequestInfo(baseURL: self.baseURL)
        info.session = self.session

        switch intent {
        case let .allocateUploadTokens(contentType):
            info.endpoint = (.post, "/v\(self.version)/allocate")
            info.queryString["content_type"] = contentType

        case let .authFacebook(accessToken):
            info.endpoint = (.post, "/v\(self.version)/facebook/auth")
            info.form = ["access_token": accessToken]

        case let .authYouTube(code):
            info.endpoint = (.post, "/v\(self.version)/youtube/auth")
            info.form["code"] = code

        case let .blockUser(identifier):
            info.endpoint = (.post, "/v\(self.version)/profile/me/blocked")
            info.queryString["identifier"] = identifier

        case let .changePassword(newPassword, oldPassword):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.form["new_password"] = newPassword
            info.form["password"] = oldPassword

        case let .changeShareLocation(share):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.queryString["share_location"] = String(share)

        case let .commentContentThread(id, text, replyTo):
            info.endpoint = (.put, "/v\(self.version)/content/\(id)/comments/")
            info.queryString["reply_to"] = replyTo
            info.queryString["text"] = text

        case let .commentContentTimeline(id, offset, text):
            info.endpoint = (.put, "/v\(self.version)/content/\(id)/comments/\(offset)")
            info.queryString["text"] = text

        case let .createContent(url, duration, tags, title, thumbnail, dimensions, relatedContent, dedupe, uploadToYouTube):
            if let dedupe = dedupe {
                info.endpoint = (.put, "/v\(self.version)/content")
                info.queryString["dedupe"] = dedupe
            } else {
                info.endpoint = (.post, "/v\(self.version)/content")
            }
            info.queryString["duration"] = String(duration)
            info.queryString["tags"] = tags.joined(separator: ",")
            if let dimensions = dimensions {
                info.queryString["width"] = String(Int(dimensions.width))
                info.queryString["height"] = String(Int(dimensions.height))
            }
            info.form["title"] = title
            if let thumbnail = thumbnail {
                info.form["image"] = FileData.from(image: thumbnail)
            }
            info.form["url"] = url.absoluteString
            info.form["upload_to_youtube"] = String(uploadToYouTube)
            if let original = relatedContent {
                original.setUpRequest(&info, prefix: "original")
            }

        case let .createContentRequest(identifier, relatedContent):
            info.endpoint = (.post, "/v\(self.version)/profile/\(identifier)/requests/")
            relatedContent.setUpRequest(&info)

        case let .createOriginalContent(ref):
            info.endpoint = (.put, "/v\(self.version)/original")
            switch ref {
            case let .metadata(creator, url, duration, title, videoURL, thumbURL):
                info.form["creator_identifier"] = creator
                info.form["url"] = url.absoluteString
                info.form["duration"] = String(duration)
                info.form["title"] = title
                info.form["video_url"] = videoURL?.absoluteString
                info.form["thumb_url"] = thumbURL?.absoluteString
            default:
                return nil
            }

        case let .createOwnContentRequest(relatedContent, delay):
            info.endpoint = (.post, "/v\(self.version)/profile/me/requests/")
            info.queryString["delay"] = String(Int(delay))
            relatedContent.setUpRequest(&info)

        case let .createPublicContentRequest(relatedContent, tags):
            info.endpoint = (.post, "/v\(self.version)/requests/public/")
            relatedContent.setUpRequest(&info)
            info.queryString["tags"] = tags.joined(separator: ",")

        case let .deleteContentComment(contentId, commentId):
            info.endpoint = (.delete, "/v\(self.version)/content/\(contentId)/comments/\(commentId)")

        case let .flagContent(id):
            info.endpoint = (.put, "/v\(self.version)/content/\(id)/flag")

        case let .follow(identifiers):
            let list = identifiers.joined(separator: ",")
            info.endpoint = (.put, "/v\(self.version)/profile/me/following/\(list)")

        case .getAccessCode:
            info.endpoint = (.post, "/v\(self.version)/code")
            info.queryString["client_id"] = "web"

        case let .getActiveContacts(identifiers):
            info.endpoint = (.post, "/v\(self.version)/contacts")
            info.body = identifiers.joined(separator: "\n").data(using: .utf8)

        case let .getContent(id):
            info.endpoint = (.get, "/v\(self.version)/content/\(id)")

        case let .getContentBySlug(slug):
            info.endpoint = (.get, "/v\(self.version)/content")
            info.queryString["slug"] = slug

        case let .getContentComments(id, sort):
            info.endpoint = (.get, "/v\(self.version)/content/\(id)/comments/")
            info.queryString["sort"] = sort

        case let .getContentList(tags, sortBy, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/content/\(tags.joined(separator: "+"))/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit.flatMap { String($0) }
            info.queryString["sort"] = sortBy

        case let .getFollowers(identifier, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/profile/\(identifier)/followers/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit.flatMap { String($0) }

        case let .getFollowing(identifier, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/profile/\(identifier)/following/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit.flatMap { String($0) }

        case .getNotifications:
            info.endpoint = (.get, "/v\(self.version)/profile/me/notifications/")

        case let .getOrCreateThread(identifier):
            info.endpoint = (.put, "/v\(self.version)/threads/")
            info.queryString["identifier"] = identifier

        case let .getOriginalContentList(sortBy, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/original/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit.flatMap { String($0) }
            info.queryString["sort"] = sortBy

        case let .getOwnContentList(tag, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/profile/me/content/\(tag)/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit

        case let .getOwnFollowers(limit, cursor, idsOnly):
            info.endpoint = (.get, "/v\(self.version)/profile/me/followers/")
            info.queryString["cursor"] = cursor
            info.queryString["ids_only"] = String(idsOnly)
            info.queryString["limit"] = limit.flatMap { String($0) }

        case let .getOwnFollowing(limit, cursor, idsOnly):
            info.endpoint = (.get, "/v\(self.version)/profile/me/following/")
            info.queryString["cursor"] = cursor
            info.queryString["ids_only"] = String(idsOnly)
            info.queryString["limit"] = limit.flatMap { String($0) }

        case let .getOwnFollowingContentList(tag, cursor):
            info.endpoint = (.get, "/v\(self.version)/profile/me/following/content/\(tag)/")
            info.queryString["cursor"] = cursor

        case .getOwnProfile:
            info.endpoint = (.get, "/v\(self.version)/profile/me")

        case .getPaymentsFeed:
            info.endpoint = (.get, "/v\(self.version)/pay/feed/")

        case let .getProfile(identifier):
            info.endpoint = (.get, "/v\(self.version)/profile/\(identifier)")

        case let .getProfileCommentList(identifier, cursor):
            info.endpoint = (.get, "/v\(self.version)/profile/\(identifier)/comments/")
            info.queryString["cursor"] = cursor

        case let .getProfileContentList(identifier, tag, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/profile/\(identifier)/content/\(tag)/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit

        case let .getProfileOriginalList(identifier, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/profile/\(identifier)/original/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit

        case let .getProfileTopPayers(identifier):
            info.endpoint = (.get, "/v\(self.version)/profile/\(identifier)/pay/top")

        case let .getPublicContentRequest(id):
            info.endpoint = (.get, "/v\(self.version)/requests/public/\(id)")

        case let .getPublicContentRequestList(tags, sortBy, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/requests/public/\(tags.joined(separator: "+"))/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit.flatMap { String($0) }
            info.queryString["sort"] = sortBy

        case let .getRelatedContentList(contentId, tag, sortBy, limit, cursor):
            info.endpoint = (.get, "/v\(self.version)/content/\(contentId)/related/\(tag)/")
            info.queryString["cursor"] = cursor
            info.queryString["limit"] = limit.flatMap { String($0) }
            info.queryString["sort"] = sortBy

        case let .getSuggestedAccounts(limit):
            info.endpoint = (.get, "/v\(self.version)/suggested")
            info.queryString["limit"] = limit.flatMap { String($0) }

        case .getTags:
            info.endpoint = (.get, "/v\(self.version)/tags")

        case let .getThreadMessages(threadId, cursor):
            info.endpoint = (.get, "/v\(self.version)/threads/\(threadId)/messages/")
            info.queryString["cursor"] = cursor

        case let .getThreads(cursor):
            info.endpoint = (.get, "/v\(self.version)/threads/")
            info.queryString["cursor"] = cursor

        case .getTopAccountsByFirst:
            info.endpoint = (.get, "/v\(self.version)/top/accounts/first")

        case .getTopAccountsByPaymentsReceived:
            info.endpoint = (.get, "/v\(self.version)/top/accounts/payments")

        case let .getTopAccountsByVotes(tag):
            info.endpoint = (.get, "/v\(self.version)/top/accounts/votes")
            info.queryString["tag"] = tag

        case .getTopCreators:
            info.endpoint = (.get, "/v\(self.version)/top/accounts/creators")

        case .getTopRewards:
            info.endpoint = (.get, "/v\(self.version)/pay/toplist/")

        case let .getYouTubeVideos(limit):
            info.endpoint = (.get, "/v\(self.version)/youtube/videos/")
            info.queryString["limit"] = limit.flatMap { String($0) }

        case let .logIn(username, password):
            info.authenticateClient = true
            info.endpoint = (.post, "/oauth2/token")
            info.queryString = [
                "grant_type": "password",
                "api_version": self.version,
            ]
            info.form = [
                "username": username,
                "password": password,
            ]

        case let .logInWithAuthCode(code):
            info.authenticateClient = true
            info.endpoint = (.post, "/oauth2/token")
            info.queryString = [
                "grant_type": "authorization_code",
                "api_version": String(self.version),
            ]
            info.form = [
                "code": code,
            ]

        case .logOut:
            // No request should be made for logging out (at least not for now).
            return nil

        case let .markNotificationSeen(id):
            info.endpoint = (.post, "/v\(self.version)/profile/me/notifications/\(id)")
            info.queryString["seen"] = "true"

        case let .messageThread(threadId, type, text, data):
            info.endpoint = (.post, "/v\(self.version)/threads/\(threadId)/messages/")
            if let data = data {
                let data = try? JSONSerialization.data(withJSONObject: data, options: [])
                info.form["data"] = data ?? "{}"
            }
            info.form["text"] = text
            info.queryString["type"] = type

        case let .pay(identifier, amount, comment):
            info.endpoint = (.post, "/v\(self.version)/profile/\(identifier)/pay/")
            info.queryString["amount"] = String(amount)
            info.form["comment"] = comment

        case let .pin(content):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            let data: DataType = ["pinned_content": content.flatMap({ PinnedContent(content: $0).data }) ?? NSNull()]
            info.form["properties"] = try? JSONSerialization.data(withJSONObject: data)

        case let .refreshSession(refreshToken):
            info.authenticateClient = true
            info.endpoint = (.post, "/oauth2/token")
            info.queryString = [
                "grant_type": "refresh_token",
                "api_version": String(self.version),
            ]
            info.form["refresh_token"] = refreshToken

        case let .register(username, password, birthday, gender):
            info.endpoint = (.post, "/v\(self.version)/register")
            if let username = username {
                info.form["username"] = username
            }
            if let password = password {
                info.form["password"] = password
            }
            if let birthday = birthday {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                info.form["birthday"] = f.string(from: birthday)
            }
            if let gender = gender {
                info.form["gender"] = gender.rawValue
            }

        case let .registerDeviceForPush(deviceId, environment, platform, token):
            info.endpoint = (.put, "/v\(self.version)/device/\(token)")
            info.queryString["environment"] = environment
            info.queryString["platform"] = platform
            info.form["device_id"] = deviceId

        case let .registerPurchase(receipt, purchases):
            info.endpoint = (.post, "/v\(self.version)/purchase/")
            info.queryString["provider"] = "itunes"
            info.queryString["purchase_id"] = purchases
            info.form["receipt"] = receipt.base64EncodedData()

        case let .report(timestamp, eventName, cls, properties):
            guard let accountId = self.session?.id else {
                return nil
            }
            var eventId = Int64(timestamp.timeIntervalSince1970 * 1000)
            if eventId == self.lastEventId {
                eventId += Int64(arc4random_uniform(50))
            } else {
                self.lastEventId = eventId
            }
            info.endpoint = (.put, "/v\(self.version)/event/\(accountId)/\(eventId)")
            info.queryString["name"] = eventName
            info.queryString["class"] = cls
            if let properties = properties {
                let properties = try? JSONSerialization.data(withJSONObject: properties, options: [])
                info.form["properties"] = properties ?? "{\"Error\":\"Failed to encode properties\"}"
            }

        case let .reportBatch(events):
            guard let accountId = self.session?.id else {
                return nil
            }
            info.endpoint = (.post, "/v\(self.version)/event/\(accountId)/batch")
            info.body = events

        case let .requestChallenge(identifier, preferPhoneCall):
            info.endpoint = (.post, "/v\(self.version)/challenge")
            info.form["identifier"] = identifier
            info.form["call"] = preferPhoneCall.description

        case let .resetPublicContentRequestEntry(requestId):
            info.endpoint = (.post, "/v\(self.version)/requests/public/\(requestId)/entry")
            info.queryString["reset"] = "true"

        case let .respondToChallenge(identifier, secret):
            info.endpoint = (.post, "/v\(self.version)/challenge/respond")
            info.form = [
                "identifier": identifier,
                "secret": secret,
            ]

        case let .searchAccounts(query):
            info.endpoint = (.get, "/v\(self.version)/profile/search")
            info.queryString["query"] = query

        case let .searchContent(query):
            info.endpoint = (.get, "/v\(self.version)/content/search")
            info.queryString["query"] = query

        case let .sendFeedback(message, email):
            info.endpoint = (.post, "/v\(self.version)/feedback")
            info.form["email"] = email
            info.form["message"] = message

        case let .sendInvite(identifiers, inviteToken, names):
            info.endpoint = (.post, "/v\(self.version)/invite")
            info.queryString["identifier"] = identifiers
            if let token = inviteToken {
                info.queryString["invite_token"] = token
            }
            if let names = names {
                info.queryString["name"] = names
            }

        case let .sendServiceInvite(service, teamId, identifiers):
            info.endpoint = (.post, "/v\(self.version)/services/\(service)/invite")
            info.queryString["team_id"] = teamId
            info.form["identifier"] = identifiers

        case let .setLocation(location):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.queryString["location"] = "\(location.coordinate.latitude),\(location.coordinate.longitude)"

        case let .submitPublicContentRequestEntry(requestId, contentId):
            info.endpoint = (.post, "/v\(self.version)/requests/public/\(requestId)/entry")
            info.queryString["content_id"] = contentId.flatMap(String.init)

        case let .submitPublicContentRequestEntryFromYouTube(requestId, videoId):
            info.endpoint = (.post, "/v\(self.version)/requests/public/\(requestId)/entry")
            info.queryString["youtube_id"] = videoId

        case let .unblockUser(identifier):
            info.endpoint = (.delete, "/v\(self.version)/profile/me/blocked/\(identifier)")

        case let .unfollow(identifier):
            info.endpoint = (.delete, "/v\(self.version)/profile/me/following/\(identifier)")

        case let .unlockPremiumProperty(property):
            info.endpoint = (.post, "/v\(self.version)/profile/me/unlock")
            info.queryString["property"] = property

        case let .unregisterDeviceForPush(deviceToken):
            info.endpoint = (.delete, "/v\(self.version)/device/\(deviceToken)")

        case let .updateContent(contentId, tags, title, thumbnail):
            info.endpoint = (.put, "/v\(self.version)/content/\(contentId)")
            info.queryString["tags"] = tags.joined(separator: ",")
            info.form["title"] = title ?? ""
            if let thumbnail = thumbnail {
                info.form["image"] = FileData.from(image: thumbnail)
            }

        case let .updateContentThumbnail(contentId, thumbnail):
            info.endpoint = (.put, "/v\(self.version)/content/\(contentId)")
            info.form["image"] = FileData.from(image: thumbnail)

        case let .updateProfile(username, image, properties):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.queryString["username"] = username
            if let image = image {
                info.form["image"] = FileData.from(image: image)
            }
            info.form["properties"] = try? JSONSerialization.data(withJSONObject: properties)

        case let .updateProfileDemographics(birthday, gender):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            info.queryString["birthday"] = f.string(from: birthday)
            info.queryString["gender"] = gender.rawValue

        case let .updateProfileDisplayName(name):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.queryString["display_name"] = name

        case let .updateProfileImage(image):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.form["image"] = FileData.from(image: image)

        case let .updateProfileProperties(properties):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.form["properties"] = try? JSONSerialization.data(withJSONObject: properties)

        case let .updateProfileUsername(username):
            info.endpoint = (.post, "/v\(self.version)/profile/me")
            info.queryString["username"] = username

        case let .uploadToYouTube(contentId):
            info.endpoint = (.post, "/v\(self.version)/youtube/upload")
            info.queryString["content_id"] = String(contentId)

        case let .updateThreadSeenUntil(threadId, messageId):
            info.endpoint = (.post, "/v\(self.version)/threads/\(threadId)/")
            info.queryString["seen_until"] = messageId

        case let .updateThreadVisibility(threadId, visible):
            info.endpoint = (.post, "/v\(self.version)/threads/\(threadId)/")
            info.queryString["visible"] = visible.description

        case let .viewContent(contentId):
            info.endpoint = (.put, "/v\(self.version)/content/\(contentId)/views")

        case let .voteForContent(contentId):
            info.endpoint = (.put, "/v\(self.version)/content/\(contentId)/votes")
        }

        return info
    }

    /// Perform an intent and report back when done.
    func performIntent(_ intent: Intent, callback: IntentCallback?) {
        guard let requestInfo = self.getRequestInfo(intent) else {
            // There was no HTTP request to make, but still report the completion of the request.
            self.reportResultForIntent(intent, result: IntentResult(data: nil, error: nil), callback: callback)
            return
        }

        let sessionManager = intent.retryable ? self.backgroundManager : self.manager

        #if DEBUG
        if case .report = intent {
        } else {
            print("\(requestInfo.method) \(requestInfo.path) \(requestInfo.queryString)")
        }
        #endif

        // Branch depending on whether there is a file to upload.
        if requestInfo.hasFiles {
            sessionManager.upload(
                multipartFormData: {
                    requestInfo.applyMultipartFormData($0)
                },
                with: requestInfo,
                encodingCompletion: {
                    switch $0 {
                    case let .success(request, _, _):
                        self.handleRequestForIntent(intent, request: request, callback: callback)
                    case let .failure(error):
                        self.reportResultForIntent(intent, result: IntentResult(data: nil, error: error), callback: callback)
                    }
                }
            )
        } else {
            let request = sessionManager.request(requestInfo)
            self.handleRequestForIntent(intent, request: request, callback: callback)
        }
    }

    /// Replaces the current session's account data with new account data.
    func updateAccountData(_ data: DataType) {
        self.session = self.session?.withNewAccountData(data)
    }

    func updateAccountData(balance: Int) {
        guard let session = self.session else {
            return
        }
        var data = session.account
        data["balance"] = NSNumber(value: balance)
        self.session = session.withNewAccountData(data)
    }

    func updateAccountData(receivingBonus: Int) {
        guard let session = self.session else {
            return
        }
        let delta = min(receivingBonus, session.bonusBalance)
        var data = session.account
        data["balance"] = session.balance + delta
        data["bonus"] = session.bonusBalance - delta
        self.session = session.withNewAccountData(data)
    }

    // MARK: - Private

    private let manager: Alamofire.SessionManager

    private var lastEventId = Int64(0)
    private var retryRequestQueue: [Intent]

    /// Performs the provided request and reports the result.
    private func handleRequestForIntent(_ intent: Intent, request: DataRequest, callback: IntentCallback?) {
        request.responseJSON {
            let statusCode = $0.response?.statusCode ?? -1

            // Technically an array would be valid JSON but we only care about dictionaries.
            let data = $0.result.value as? DataType

            // Look for several error cases and ensure error is set if they have occurred.
            var finalError = $0.result.error
            if let errorInfo = data?["error"] as? DataType {
                finalError = BackendError(statusCode: statusCode, info: errorInfo)
            }
            if finalError == nil && !(200...299 ~= statusCode) {
                finalError = NSError(
                    domain: "cam.reaction.api",
                    code: statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP code \(statusCode)"]
                )
            }

            if statusCode != -1 {
                // The request reached the backend. Attempt to send anything that is pending.
                self.attemptFlushRetryQueue()
            } else if intent.retryable {
                // The request failed and is retryable, add it to the retry queue.
                NSLog("%@", "WARNING: Retryable intent \(intent) failed")
                self.retryRequestQueue.append(intent)
            }

            // Report the result of the request.
            self.reportResultForIntent(intent, result: IntentResult(data: data, error: finalError, code: statusCode), callback: callback)
        }
    }

    /// Reports the result of performing an intent by calling the callback. Also updates internal state.
    private func reportResultForIntent(_ intent: Intent, result: IntentResult, callback: IntentCallback?) {
        #if DEBUG
        if case .report = intent {
        } else {
            if let requestInfo = self.getRequestInfo(intent) {
                print("\(requestInfo.method) \(requestInfo.path) \(requestInfo.queryString): \(result.code)")
                if let error = result.error {
                    print("> \(error.localizedDescription)")
                }
            }
        }
        #endif

        if result.code == 401 {
            switch intent {
            case .getOwnContentList, .getOwnFollowers, .getOwnFollowing,
                 .getOwnFollowingContentList, .getOwnProfile:
                if self.session != nil {
                    Logging.danger("Clearing Session", ["Reason": "401 for \(intent)"])
                } else {
                    Logging.warning("Clearing Session (Hypothetically)", ["Reason": "401 for \(intent)"])
                }
                // Clear the session for some requests that should work but got 401.
                self.session = nil
            default:
                Logging.warning("HTTP Error 401", ["Intent": String(describing: intent)])
            }
        }

        // Perform internal state updates based on intents and their outcomes.
        switch intent {
        case .authFacebook, .authYouTube:
            // TODO: Consider bundling these with the case below.
            guard
                result.successful,
                let data = result.data,
                let account = data["account"] as? DataType,
                let accountId = account["id"] as? Int64,
                accountId == self.session?.id
                else { break }
            self.updateAccountData(account)
        case .logIn, .logInWithAuthCode, .refreshSession, .register, .respondToChallenge:
            // Update the session for intents that result in new session data.
            guard result.successful, let data = result.data else {
                break
            }
            self.session = Session(data, timestamp: Date())
        case .logOut:
            // Clear the session for the log out intent.
            self.session = nil
        case .changePassword, .changeShareLocation, .getOwnProfile, .pin, .setLocation,
             .updateProfile, .updateProfileDemographics, .updateProfileDisplayName,
             .updateProfileImage, .updateProfileProperties, .updateProfileUsername:
            // Update the current session's account data when we get or update the user's profile.
            guard result.successful, let data = result.data else {
                break
            }
            if let status = data["status"] as? String, status == "banned" {
                SettingsManager.isTainted = true
                self.session = nil
                break
            }
            self.updateAccountData(data)
        case .pay, .registerPurchase:
            guard result.successful, let data = result.data?["wallet"] as? DataType else {
                break
            }
            let wallet = Wallet(data: data)
            self.updateAccountData(balance: wallet.balance)
        case .registerDeviceForPush:
            guard result.successful, let build = result.data?["minimum_build"] as? Int else {
                break
            }
            SettingsManager.minimumBuild = build
        default:
            break
        }

        // Finally call the callback (if any) with the result.
        callback?(result)
    }

    private func attemptFlushRetryQueue() {
        guard self.retryRequestQueue.count > 0 else {
            return
        }
        let retries = self.retryRequestQueue
        self.retryRequestQueue.removeAll()
        for intent in retries {
            if case .report = intent {
            } else {
                Logging.debug("Backend Client Retry", [
                    "Status": "Starting",
                    "Intent": String(describing: intent)])
            }
            intent.performWithBackgroundTask(self) {
                if case .report = intent {
                } else if case .reportBatch = intent {
                } else {
                    Logging.debug("Backend Client Retry", ["Status": $0.successful ? "Succeeded" : "Failed"])
                }
            }
        }
    }
}

class BackendError: NSError {
    override var localizedDescription: String {
        guard let message = self.userInfo["message"] as? String else {
            return super.localizedDescription
        }
        return message
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    init(statusCode: Int, info: [String: Any]) {
        var code = info["code"] as? Int ?? -1
        if code == -1 {
            // Fall back to the status code for undefined error codes.
            code = statusCode
        }
        super.init(domain: "cam.reaction.api", code: code, userInfo: info)
    }
}

private class FileData {
    let data: Data
    let name: String
    let mimeType: String

    init(data: Data, name: String, mimeType: String) {
        self.data = data
        self.name = name
        self.mimeType = mimeType
    }

    static func from(image: Intent.Image) -> FileData {
        let data: Data
        let filename, mimetype: String
        switch image {
        case let .jpeg(imageData):
            data = imageData
            filename = "image.jpg"
            mimetype = "image/jpeg"
        case let .png(imageData):
            data = imageData
            filename = "image.png"
            mimetype = "image/png"
        }
        return FileData(data: data, name: filename, mimeType: mimetype)
    }
}

/// Represents information needed to make an HTTP request to the API.
struct RequestInfo: URLRequestConvertible {
    private let baseURL: URL
    var authenticateClient = false
    var method = HTTPMethod.get
    var path = "/"
    var session: Session?
    /// Query string parameters to put in the URL.
    var queryString = [String: Any]()
    /// Form data that should go in the HTTP body (only for POST).
    var form = [String: Any]()
    /// The HTTP Body
    var body: Data?

    /// Convenience property for assigning method and path at the same time as a tuple.
    var endpoint: (method: HTTPMethod, path: String) {
        get {
            return (self.method, self.path)
        }
        set {
            self.method = newValue.method
            self.path = newValue.path
        }
    }

    /// Checks if any fields point at local file URLs or NSData objects.
    var hasFiles: Bool {
        return self.form.values.contains { $0 is FileData || $0 is Data || $0 is URL }
    }

    /// The URL for the request (note: without the query string values).
    var url: URL {
        return self.baseURL.appendingPathComponent(self.path)
    }

    static var userAgentPieces: [(String, String)] = {
        let os = ProcessInfo().operatingSystemVersion
        return [
            ("ReactionCam", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "UNKNOWN"),
            ("VoiceOver", UIAccessibilityIsVoiceOverRunning() ? "1" : "0"),
            ("Darwin", String(format: "%i.%i.%i", os.majorVersion, os.minorVersion, os.patchVersion)),
            ("Model", UIDevice.current.modelIdentifier),
            ("gzip", "1"),
        ]
    }()

    static var userAgent: String = {
        return RequestInfo.userAgentPieces.map { (key, value) in "\(key)/\(value)" }.joined(separator: " ")
    }()

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func applyMultipartFormData(_ multipart: MultipartFormData) {
        func append(_ name: String, value: Any) {
            switch value {
            case let data as Data:
                multipart.append(data, withName: name)
            case let file as FileData:
                multipart.append(file.data, withName: name, fileName: file.name, mimeType: file.mimeType)
            case let url as URL:
                multipart.append(url, withName: name)
            default:
                let data = String(describing: value).data(using: .utf8)!
                multipart.append(data, withName: name)
            }
        }

        for (fieldName, value) in self.form {
            if let array = value as? [Any] {
                array.forEach {
                    append(fieldName, value: $0)
                }
            } else {
                append(fieldName, value: value)
            }
        }
    }

    // MARK: URLRequestConvertible

    func asURLRequest() -> URLRequest {
        var request = URLRequest(url: self.url)

        if self.authenticateClient {
            // Basic client auth.
            request.setValue("Basic cmVhY3Rpb25jYW06eTFxZkR5NHRvY1JPR2dKajVlWGl5MXFmRHk0dG9jUk9HZ0pqNWVYaQ==", forHTTPHeaderField: "Authorization")
        } else if let token = self.session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.setValue(RequestInfo.userAgent, forHTTPHeaderField: "User-Agent")

        if let language = Locale.preferredLanguages.first {
            request.setValue(language, forHTTPHeaderField: "Accept-Language")
        }

        // Add the query string parameters to the path.
        if self.queryString.count > 0 {
            if let r = try? URLEncoding.default.encode(request, with: self.queryString) {
                request = r
            }
        }

        // Apply method after query string so that Alamofire doesn't put it in the HTTP body.
        request.httpMethod = self.method.rawValue
        if let httpBody = self.body {
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody
        }

        // Apply form data here if there are no files to upload. Files are added in applyMultipartFormData.
        if self.form.count > 0 && !self.hasFiles {
            precondition(self.method == .post || self.method == .put, "Form data can only be added to POST requests")
            if let r = try? URLEncoding.default.encode(request, with: self.form) {
                request = r
            }
        }

        return request
    }
}
