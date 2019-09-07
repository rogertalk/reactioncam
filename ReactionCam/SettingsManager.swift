import CloudKit
import iRate
import TwitterKit
import UIKit

private enum SettingsKey: String {
    /// Setting for whether videos should be automatically posted to Facebook.
    case autopostFacebook
    /// Setting for whether videos should be automatically posted to Instagram
    case autopostIGTV
    /// Setting for whether videos should be automatically posted to IGTV
    case autopostInstagram
    /// Setting for whether videos should be automatically posted to Tumblr
    case autopostTumblr
    /// Setting for whether videos should be automatically posted to Twitter.
    case autopostTwitter
    /// Setting for whether videos should be automatically posted to YouTube.
    case autopostYouTube
    /// Setting for whether videos should be automatically Saved to Camera Roll.
    case autoSave
    /// Tracks whether the user has ever shared the app to friends.
    case userDidShare
    /// The ids of content that has been flagged (should be hidden).
    case flaggedContentIds
    /// The set of tags the user is following.
    case followedTags
    /// Whether the user has seen the "Tap to change" CTA.
    case hasSeenChangeLayoutCTA
    /// If the introduction for public requests has been seen by the user.
    case hasSeenPublicRequestIntro
    /// Account ids that the user may want to follow.
    case interestingAccountIds
    /// Instagram OAuth Token
    case instagramOAuthToken
    /// The last time the user saw the "NOW" feed.
    case lastFeedView
    /// The hue (color) of the marker in presentation mode.
    case markerHue
    /// The minimum build we want the user to have installed.
    case minimumBuild
    /// Holds a dictionary of badge identifiers to number of interactions.
    case newBadgeInteractions
    /// Accounts that the user has recently interacted with.
    case recentAccountIds
    /// The quality to record with.
    case recordQuality
    /// Requests that have been seen by the current user.
    case seenRequestIds
    /// Setting if edit profile has been shown.
    case showEditProfile
    /// Flag for whether we have suggested user's friends to user.
    case suggestFriends
    /// Flag for whether this user is associated with a banned account.
    case tainted
    /// Tumblr auth token.
    case tumblrOAuthToken
    /// Tumblr auth token secret.
    case tumblrOAuthTokenSecret
    /// Twitter access token.
    case twitterAccessToken
}

enum SearchContext {
    case web, video
}

class SettingsManager {
    // MARK: - Constants

    static let defaultBio = "Subscribe to my channel to stay up to date with my videos! 😍"

    static let followersTitleMaxLength = 14
    static let watermarkMaxLength = 30

    static let shareBadges = [
        "🙌",
        "💎",
        "🏆",
        "👋",
        "👌",
        "🤘",
        "🌝",
        "🏅",
        "🚀",
        "🎉",
        "🤑",
        "👑",
        "🤣",
        "🎯",
        "💯",
        "🔑",
        "🙏",
        "✨",
    ]

    static let shareFileExcludedActivityTypes: [UIActivityType] = [
        .addToReadingList,
        .assignToContact,
        .copyToPasteboard,
        .mail,
        .openInIBooks,
        .postToFlickr,
        .postToVimeo,
        .print,
        // TODO: Remove this in the future.
        //.saveToCameraRoll,
        UIActivityType(rawValue: "com.apple.mobilenotes.SharingExtension"),
        UIActivityType(rawValue: "com.apple.reminders.RemindersEditorExtension"),
    ]

    static let shareLinkExcludedActivityTypes: [UIActivityType] = [
        .addToReadingList,
        .assignToContact,
        .mail,
        .openInIBooks,
        .postToFlickr,
        .postToVimeo,
        .print,
        .saveToCameraRoll,
        UIActivityType(rawValue: "com.apple.mobilenotes.SharingExtension"),
        UIActivityType(rawValue: "com.apple.reminders.RemindersEditorExtension"),
    ]

    static let youTubeClientId = "883081244667-43i0eip54je245tj0ff904tr8g1t9q5h.apps.googleusercontent.com"

    static let youTubeScopes = [
        "email",
        "https://www.googleapis.com/auth/youtube.readonly",
        "https://www.googleapis.com/auth/youtube.upload",
        "https://www.googleapis.com/auth/yt-analytics.readonly",
    ]

    // MARK: - Computed values

    static var helpURL: URL {
        return URL(string: "https://www.reaction.cam/help")!
    }

    static var helpArtistsURL: URL {
        return URL(string: "https://www.reaction.cam/artists")!
    }

    static var helpArtistsSignUpURL: URL {
        return URL(string: "https://www.reaction.cam/artists/signup")!
    }

    static var helpCoinsURL: URL {
        return URL(string: "https://www.reaction.cam/help/coins")!
    }

    static var helpGetMoreViewsURL: URL {
        return URL(string: "https://www.reaction.cam/help/share")!
    }

    static var helpPromoteURL: URL {
        return URL(string: "https://www.reaction.cam/help/promote")!
    }

    static var helpReactToSocialURL: URL {
        return URL(string: "https://www.reaction.cam/help/react-to-social-media")!
    }

    static var helpVerificationURL: URL {
        return URL(string: "https://www.reaction.cam/help/verification")!
    }

    static var initialCreationURL: URL {
        return URL(string: "https://www.reaction.cam/x/start")!
    }

    static var markerColor: UIColor {
        return UIColor(hue: CGFloat(self.markerHue / 360), saturation: 1, brightness: 1, alpha: 1)
    }

    static var randomURL: URL {
        return URL(string: "https://www.reaction.cam/x/random")!
    }

    static var shouldAskToRate: Bool {
        guard !self.didAskToRate else {
            return false
        }
        guard let rate = iRate.sharedInstance() else {
            return false
        }
        return rate.eventCount >= rate.eventsUntilPrompt &&
            !rate.ratedThisVersion &&
            (!rate.ratedAnyVersion || rate.promptForNewVersionIfUserRated)
    }

    static var shouldAskToShare: Bool {
        return !self.didAskToShare && !self.userDidShare
    }

    static var youTubeAuthURL: URL {
        let parameters = [
            "access_type": "offline",
            "client_id": self.youTubeClientId,
            "scope": self.youTubeScopes.joined(separator: " "),
            "redirect_uri": "cam.reaction.ReactionCam:/youtube_oauth2redirect",
            "response_type": "code",
        ]
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = parameters.map { URLQueryItem(name: $0, value: $1) }
        return components.url!
    }

    // MARK: - In-memory settings

    static var didAskToRate = false
    static var didAskToShare = false
    static var preferFrontCamera = true

    private(set) static var recentAccounts = [Account]() {
        didSet {
            self.recentAccountIds = self.recentAccounts.map { $0.id }
        }
    }

    // MARK: - Persisted settings

    static var autopostFacebook: Bool {
        get { return getBool(.autopostFacebook) }
        set { set(.autopostFacebook, to: newValue) }
    }

    static var autopostIGTV: Bool {
        get { return getBool(.autopostIGTV) }
        set { set(.autopostIGTV, to: newValue) }
    }

    static var autopostInstagram: Bool {
        get { return getBool(.autopostInstagram) }
        set { set(.autopostInstagram, to: newValue) }
    }

    static var autopostTwitter: Bool {
        get { return getBool(.autopostTwitter) }
        set { set(.autopostTwitter, to: newValue) }
    }

    static var autopostTumblr: Bool {
        get { return getBool(.autopostTumblr) }
        set { set(.autopostTumblr, to: newValue) }
    }

    static var autopostYouTube: Bool {
        get { return getBool(.autopostYouTube) }
        set { set(.autopostYouTube, to: newValue) }
    }

    static var didChangeLayout: Bool {
        get { return getBool(.hasSeenChangeLayoutCTA) }
        set { set(.hasSeenChangeLayoutCTA, to: newValue) }
    }

    static var didSeePublicRequestIntro: Bool {
        get { return getBool(.hasSeenPublicRequestIntro) }
        set { set(.hasSeenPublicRequestIntro, to: newValue) }
    }

    static var didSuggestFriends: Bool {
        get { return getBool(.suggestFriends) }
        set { set(.suggestFriends, to: newValue) }
    }

    static var editProfileShown: Bool {
        get { return getBool(.showEditProfile) }
        set { set(.showEditProfile, to: newValue) }
    }
    
    static var flaggedContentIds: [Int64] {
        get { return (get(.flaggedContentIds) as? [Int64]) ?? [] }
        set { set(.flaggedContentIds, to: newValue) }
    }

    static var followedTags: [String] {
        get { return (get(.followedTags) as? [String]) ?? [] }
        set { set(.followedTags, to: newValue) }
    }

    static var interestingAccountIds: [Int64] {
        get { return (get(.interestingAccountIds) as? [Int64]) ?? [] }
        set { set(.interestingAccountIds, to: newValue) }
    }

    static var instagramOAuthToken: String? {
        get { return get(.instagramOAuthToken) as? String }
        set { set(.instagramOAuthToken, to: newValue) }
    }

    static var isTainted: Bool {
        get {
            if NSUbiquitousKeyValueStore.default.bool(forKey: "tainted") {
                return true
            }
            return getBool(.tainted)
        }
        set {
            // Tainted flag persists across reinstalls and devices.
            if newValue {
                NSUbiquitousKeyValueStore.default.set(true, forKey: "tainted")
            } else {
                NSUbiquitousKeyValueStore.default.removeObject(forKey: "tainted")
            }
            set(.tainted, to: newValue)
        }
    }

    static var lastFeedView: Date {
        get { return (get(.lastFeedView) as? Date) ?? Date.distantPast }
        set { set(.lastFeedView, to: newValue) }
    }

    static var markerHue: Float {
        get { return getFloat(.markerHue) }
        set { set(.markerHue, to: newValue) }
    }

    static var minimumBuild: Int {
        get { return getInt(.minimumBuild) }
        set { set(.minimumBuild, to: newValue) }
    }

    static var recordQuality: MediaWriterSettings.Quality {
        get {
            guard let v = getString(.recordQuality), let q = MediaWriterSettings.Quality(rawValue: v) else {
                return .medium
            }
            return q
        }
        set { set(.recordQuality, to: newValue.rawValue) }
    }

    static var recentAccountIds: [Int64] {
        get { return (get(.recentAccountIds) as? [Int64]) ?? [] }
        set { set(.recentAccountIds, to: newValue) }
    }

    static var userDidShare: Bool {
        get { return getBool(.userDidShare) }
        set { set(.userDidShare, to: newValue) }
    }

    static var tumblrOAuthToken: String? {
        get { return get(.tumblrOAuthToken) as? String }
        set { set(.tumblrOAuthToken, to: newValue) }
    }

    static var tumblrOAuthTokenSecret: String? {
        get { return get(.tumblrOAuthTokenSecret) as? String }
        set { set(.tumblrOAuthTokenSecret, to: newValue) }
    }

    // MARK: - Methods

    static func addInterestingAccounts(ids: [Int64]) {
        let uniqueIds = Set(self.interestingAccountIds + ids)
        self.interestingAccountIds = Array(uniqueIds)
    }

    static func getChannelURL(username: String) -> String {
        return "https://reaction.cam/\(username.replacingOccurrences(of: " ", with: ""))"
    }

    static func isVideo(url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "avi", "mov", "m3u8", "mp4":
            return true
        default:
            break
        }
        switch url.host {
        case .some("storage.googleapis.com"):
            return url.path.hasPrefix("/rcam/")
        case .some("d32au24mly9y2n.cloudfront.net"), .some("s.reaction.cam"):
            return true
        default:
            return false
        }
    }

    static func loadRecentAccounts() {
        self.recentAccountIds.forEach {
            Intent.getProfile(identifier: String($0)).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    return
                }
                self.recentAccounts.append(Profile(data: data))
            }
        }
    }

    static func hasSeenRequest(id: Int64) -> Bool {
        let ids: [Int64] = getArray(.seenRequestIds)
        return ids.contains(id)
    }

    static func markRequestSeen(id: Int64) {
        var ids: [Int64] = getArray(.seenRequestIds)
        guard !ids.contains(id) else { return }
        ids.append(id)
        set(.seenRequestIds, to: ids)
    }

    static func reportNewBadgeInteraction(for identifier: String) {
        let interactions = (self.newBadgeInteractions[identifier]?.intValue ?? 0) + 1
        self.newBadgeInteractions[identifier] = NSNumber(integerLiteral: interactions)
    }

    static func resetUser() {
        let keysToClear: [SettingsKey] = [
            .autopostFacebook, .autopostIGTV, .autopostInstagram, .autopostTumblr, .autopostTwitter,
            .autopostYouTube, .followedTags, .lastFeedView, .recentAccountIds, .showEditProfile,
            .suggestFriends, .tumblrOAuthToken, .tumblrOAuthTokenSecret, .twitterAccessToken,
        ]
        for key in keysToClear {
            defaults.removeObject(forKey: key.rawValue)
        }
        if let twitterUser = TWTRTwitter.sharedInstance().sessionStore.session() {
            TWTRTwitter.sharedInstance().sessionStore.logOutUserID(twitterUser.userID)
        }
    }

    static func searchURL(for query: String, context: SearchContext = .web) -> URL {
        var address: URLComponents
        switch context {
        case .web:
            address = URLComponents(string: "https://www.google.com/search")!
        case .video:
            address = URLComponents(string: "https://m.youtube.com/results")!
        }
        address.queryItems = [URLQueryItem(name: "q", value: query)]
        return address.url!
    }

    static func shareChannelCopy(account: Account?) -> String {
        guard let account = account else {
            return "This reaction.cam app is LIT 😂 watch and make your own reaction videos! https://reaction.cam/app"
        }
        if account.isCurrentUser {
            if let session = BackendClient.api.session, session.hasBeenOnboarded {
                return "This reaction.cam app is LIT 😂 subscribe to me @\(session.username) and make your own reaction videos! \(getChannelURL(username: session.username))"
            }
            return "This reaction.cam app is LIT 😂 subscribe to me and make your own reaction videos! https://reaction.cam/app"
        }
        return "This reaction.cam app is LIT 😂 subscribe to @\(account.username) and make your own reaction videos! \(getChannelURL(username: account.username))"
    }

    static func shareStreakCopy(days: Int) -> String {
        if let session = BackendClient.api.session, session.hasBeenOnboarded {
            return "I'm on a \(days)-day streak! 🚨 \(self.getChannelURL(username: session.username))"
        }
        return "I'm on a \(days)-day streak! 🚨 https://reaction.cam/app"
    }

    static func shouldShowNewBadge(for identifier: String) -> Bool {
        return (self.newBadgeInteractions[identifier]?.intValue ?? 0) < self.minimumNewBadgeInteractions
    }

    @discardableResult
    static func toggleFlaggedContent(id: Int64, value: Bool? = nil) -> [Int64] {
        var flaggedContentIds = self.flaggedContentIds
        if let index = flaggedContentIds.index(of: id) {
            if value != true {
                flaggedContentIds.remove(at: index)
            }
        } else if value != false {
            flaggedContentIds.append(id)
        }
        self.flaggedContentIds = flaggedContentIds
        return flaggedContentIds
    }

    static func trackRecentAccount(_ account: Account) {
        if let index = self.recentAccounts.index(where: { $0.id == account.id }) {
            self.recentAccounts.remove(at: index)
        } else if self.recentAccounts.count == 7 {
            self.recentAccounts.removeLast()
        }
        self.recentAccounts.insert(account, at: 0)
    }

    // MARK: - Private

    private static let minimumNewBadgeInteractions = 1

    private static var newBadgeInteractions: [String: NSNumber] {
        get {
            guard let data = get(.newBadgeInteractions) as? Data else {
                return [:]
            }
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: NSNumber] ?? [:]
        }
        set {
            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            set(.newBadgeInteractions, to: data)
        }
    }
}

private let defaults = UserDefaults.standard

private func get(_ key: SettingsKey) -> Any? {
    return defaults.object(forKey: key.rawValue)
}

private func getArray<T>(_ key: SettingsKey) -> [T] {
    guard let array = defaults.array(forKey: key.rawValue) else {
        return []
    }
    return (array as? [T]) ?? []
}

private func getBool(_ key: SettingsKey) -> Bool {
    return defaults.bool(forKey: key.rawValue)
}

private func getFloat(_ key: SettingsKey) -> Float {
    return defaults.float(forKey: key.rawValue)
}

private func getInt(_ key: SettingsKey) -> Int {
    return defaults.integer(forKey: key.rawValue)
}

private func getString(_ key: SettingsKey) -> String? {
    return defaults.string(forKey: key.rawValue)
}

private func set(_ key: SettingsKey, to value: Any?) {
    defaults.set(value, forKey: key.rawValue)
}
