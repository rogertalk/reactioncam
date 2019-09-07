import AlamofireImage
import AVFoundation
import Crashlytics
import Fabric
import FBSDKCoreKit
import FBSDKLoginKit
import Firebase
import iRate
import StoreKit
import TMTumblrSDK
import TwitterKit
import UIKit
import UserNotifications

enum DeepLinkResult {
    case browser(URL)
    case content(Content, react: Bool)
    case failed
    case profile(Profile)
    case tag(String)
}

struct NotificationEvent {
    let type: String
    let data: [String: Any]
}

enum NotificationPermissionRequest: String {
    case normal, reminder
}

enum NotificationEventResult {
    case invalidData, other
    case chatChannel(String)
    case content(ContentInfo)
    case contentComment(ContentInfo, Comment)
    case notificationScreenUpdate
    case openURL(URL)
    case threadMessage(MessageThread)
}

enum EventClass: String {
    case normal = ""
    case debug, success, info, warning, danger
}

@UIApplicationMain
class AppDelegate: UIResponder,
    CrashlyticsDelegate,
    iRateDelegate,
    UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    let storyboard: UIStoryboard
    var window: UIWindow?

    /// Fired when the application changes between active/inactive states.
    static let applicationActiveStateChanged = Event<Bool>()
    /// Fired when the user has granted notifications to be shown.
    static let userNotificationsGranted = Event<Void>()

    override init() {
        self.storyboard = UIStoryboard(name: "Main", bundle: nil)
        super.init()
    }

    static func connectFacebook(presenter: UIViewController, callback: @escaping (Bool) -> ()) {
        let loginManager = FBSDKLoginManager()

        let handleAuthFacebook = { (result: IntentResult) in
            if result.successful, let data = result.data, let session = Session(data, timestamp: Date()) {
                if let oldSession = BackendClient.api.session, session.id != oldSession.id {
                    // *Theoretically* this shouldn't happen, but just in case...
                    Logging.danger("Facebook Auth Error", ["Error": "Somehow logged into another account while logged in"])
                    callback(false)
                    return
                }
                BackendClient.api.session = session
                callback(true)
                return
            }
            loginManager.logOut()
            if result.code == 409 {
                Logging.warning("Facebook Auth Error", ["Error": "Already connected by another account"])
                let alert = UIAlertController(
                    title: "Uh-oh!",
                    message: "That Facebook account has already been connected to another reaction.cam account. Please reach out to us at yo@reaction.cam or by tapping Help below for assistance.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Help", style: .default) { _ in
                    HelpViewController.showHelp(presenter: presenter)
                })
                alert.addCancel(title: "Back")
                presenter.present(alert, animated: true)
            } else {
                Logging.warning("Facebook Auth Error", ["Error": result.error?.localizedDescription ?? "Unknown"])
                let alert = AnywhereAlertController(title: "Oops!", message: "Something went wrong. Please try again.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                presenter.present(alert, animated: true)
            }
            callback(false)
        }

        if let token = FBSDKAccessToken.current() {
            // We already have a Facebook token.
            if let session = BackendClient.api.session, session.hasService(id: "facebook", resource: token.userID) {
                // Nothing to do.
                callback(true)
                return
            }
            // Add the current Facebook token to the account (or log in if we were not logged in).
            Intent.authFacebook(accessToken: token.tokenString).perform(BackendClient.api, callback: handleAuthFacebook)
            return
        }

        loginManager.logIn(withReadPermissions: ["email", "user_friends"], from: nil) { result, error in
            guard let fbSession = result, let token = fbSession.token else {
                Logging.warning("Facebook Error", ["Error": error?.localizedDescription ?? "Unknown"])
                callback(false)
                return
            }
            if let session = BackendClient.api.session, session.hasService(id: "facebook", resource: token.userID) {
                // No need to report to the backend since it already knows about this Facebook account.
                callback(true)
                return
            }
            Intent.authFacebook(accessToken: token.tokenString).perform(BackendClient.api, callback: handleAuthFacebook)
        }
    }

    static func getBatteryLevel() -> Float {
        let d = UIDevice.current
        d.isBatteryMonitoringEnabled = true
        let level = d.batteryLevel
        d.isBatteryMonitoringEnabled = false
        return level
    }

    static func handleDeepLink(url: URL) -> Bool {
        return self.handleDeepLink(url, callback: { self.handleDeepLinkResult($0) })
    }

    static func handleDeepLink(_ url: URL, callback: @escaping (DeepLinkResult) -> ()) -> Bool {
        guard url.host == "rcam.at" || url.host == "reaction.cam" || url.host == "www.reaction.cam" else {
            return false
        }
        let callbackOnMain = { result in DispatchQueue.main.async { callback(result) } }
        // Standardize legacy paths (we may need to disambiguate some paths).
        let fallbackToContent: Bool
        let path: String
        if url.path.starts(with: "/@") {
            fallbackToContent = false
            path = "/\(url.path.dropFirst(2))"
        } else if url.path.starts(with: "/u/") {
            fallbackToContent = false
            path = "/\(url.path.dropFirst(3))"
        } else {
            fallbackToContent = true
            path = url.path
        }
        // Force user back into browser for certain core paths due to Apple bug.
        // rdar://37505243
        if path == "/" || path == "/artists" || path.starts(with: "/artists/") || path == "/help" || path.starts(with: "/help/") || path == "/terms" {
            callbackOnMain(.browser(url))
            return true
        }
        // Utility function that looks up content by slug and calls the callback.
        let lookupContent = { (slug: String) in
            ContentService.instance.getContent(slug: slug) {
                guard let content = $0 else {
                    callbackOnMain(.failed)
                    return
                }
                callbackOnMain(.content(content, react: url.fragment == "react"))
            }
        }
        // Handle different path prefixes.
        if path.starts(with: "/t/") {
            callbackOnMain(.tag(String(path.dropFirst(3))))
        } else if path.starts(with: "/v/") {
            lookupContent(String(path.dropFirst(3)))
        } else {
            let username = String(path.dropFirst())
            Intent.getProfile(identifier: username).performWithoutDispatch(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    if fallbackToContent {
                        // Try to look up the non-existing username as a content slug instead.
                        lookupContent(username)
                    } else {
                        callbackOnMain(.failed)
                    }
                    return
                }
                callbackOnMain(.profile(Profile(data: data)))
            }
        }
        return true
    }

    @discardableResult
    static func handleDeepLinkResult(_ result: DeepLinkResult) -> Bool {
        // Ensure either a valid account or that we have not yet gone through onboarding.
        // Prevent cases where user logs out then deep links elsewhere into app.
        guard BackendClient.api.session != nil || TabBarController.instance == nil else {
            return false
        }
        switch result {
        case let .browser(url):
            UIApplication.shared.open(url)
        case let .content(content, react):
            if react {
                TabBarController.showCreate(content: content, source: "Deep Link")
            } else if content.isOriginal {
                TabBarController.select(originalContent: content, source: "Deep Link")
            } else {
                TabBarController.select(content: content)
            }
        case let .profile(profile):
            TabBarController.select(account: profile)
        case let .tag(tag):
            TabBarController.select(tags: [tag])
        case .failed:
            return false
        }
        return true
    }

    @discardableResult
    static func handlePendingDeepLink() -> Bool {
        guard let result = self.pendingDeepLinkResult else {
            return false
        }
        self.pendingDeepLinkResult = nil
        return self.handleDeepLinkResult(result)
    }

    static func notifyIfSquelched() {
        let count = AppDelegate.notifsSquelched
        guard count > 0 else {
            return
        }
        AppDelegate.notifsSquelched = 0
        let content = UNMutableNotificationContent()
        content.body = "🤓 You missed \(count) notif\(count == 1 ? "" : "s") while recording.\nCheck your Inbox tab!"
        content.categoryIdentifier = "cam.reaction.squelchedNotification"
        content.userInfo["api_version"] = 50
        content.userInfo["type"] = "squelched-notifs"
        let notif = UNNotificationRequest(identifier: "SquelchedNotif", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        UNUserNotificationCenter.current().add(notif, withCompletionHandler: nil)
    }

    static func requestNotificationPermissions(source: String, primer: String, callback: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus != .denied else {
                DispatchQueue.main.async {
                    UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                }
                return
            }
            center.requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
                guard granted else {
                    Logging.danger("Permission Denied", [
                        "Permission": "Notifications",
                        "Source": source,
                        "Primer": primer])
                    NSLog("%@", "WARNING: Did not get notification permission: \(String(describing: error))")
                    DispatchQueue.main.async {
                        callback(false)
                    }
                    return
                }
                Logging.success("Permission Granted", [
                    "Permission": "Notifications",
                    "Source": source,
                    "Primer": primer])
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                    callback(true)
                }
                AppDelegate.userNotificationsGranted.emit()
            }
        }
    }

    static func requestNotificationPermissions(presentAlertWith viewController: UIViewController, source: String, type: NotificationPermissionRequest = .normal, callback: @escaping (Bool) -> Void) {
        Logging.debug("Notification Permission (Fake)", ["Source": source, "Type": type.rawValue])
        var title: String
        var message: String
        var enable: String
        var decline: String
        var primer: String
        switch type {
        case .normal:
            title = "Turn on notifications?"
            message = "We'll make sure you don't miss out when you get requests or messages from artists or your subscribers."
            enable = "Yes! 🙌"
            decline = "Later"
            primer = "normal"
        case .reminder:
            title = "Turn on notifications?"
            message = "Don't miss another important notification! 😵"
            enable = "Yes! 🙌"
            decline = "Not Now"
            primer = "reminder"
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addCancel(title: decline) {
            Logging.warning("Permission Deferred", [
                "Permission": "Notifications",
                "Source": source,
                "Primer": primer])
            alert.dismiss(animated: true)
            callback(false)
        }
        let cta = UIAlertAction(title: enable, style: .default) { _ in
            AppDelegate.requestNotificationPermissions(source: source, primer: primer, callback: callback)
        }
        alert.addAction(cta)
        alert.preferredAction = cta
        viewController.present(alert, animated: true)
    }

    // MARK: - CrashlyticsDelegate

    func crashlyticsDidDetectReport(forLastExecution report: CLSReport) {
        Logging.danger("Crash Detected", [
            "Identifier": report.identifier,
            "Timestamp": report.dateCreated.description])
    }

    // MARK: - UIApplicationDelegate

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        Logging.log("Continue User Activity", [
            "ActivityType": userActivity.activityType,
            "URL": userActivity.webpageURL?.absoluteString ?? "N/A"])
        guard let url = userActivity.webpageURL else {
            return false
        }
        return AppDelegate.handleDeepLink(url: url)
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey: Any] = [:]) -> Bool {
        guard
            !FBSDKApplicationDelegate.sharedInstance().application(app, open: url, options: options),
            !TWTRTwitter.sharedInstance().application(app, open: url, options: options),
            !TMAPIClient.sharedInstance().handleOpen(url)
            else {
                return false
        }

        guard let scheme = url.scheme else {
            return false
        }

        // YouTube connect.
        if url.path == "/youtube_oauth2redirect" {
            let info = url.parseQueryString()
            if let authCode = info["code"]?.first {
                Logging.log("YouTube Connect", ["Result": "Received Auth Code"])
                ContentService.instance.exchangeCode(service: "youtube", authCode: authCode)
            } else {
                if let error = info["error"] {
                    Logging.danger("YouTube Connect", ["Result": "Failed", "Error": error])
                }
                ContentService.instance.exchangeCode(service: "youtube", authCode: nil)
            }
            return true
        }

        guard let host = url.host else {
            return false
        }

        switch (scheme, host) {
        case ("reactioncam", "content"):
            if let id = Int64(url.lastPathComponent),
                let tag = url.parseQueryString()["v"]?.first {
                switch tag {
                case "original":
                    ContentService.instance.getContent(id: id) {
                        guard let content = $0 else {
                            return
                        }
                        TabBarController.select(originalContent: content, source: "Launch URI")
                    }
                case "reaction":
                    TabBarController.select(contentId: id)
                default:
                    return false
                }
            }
        case ("reactioncam", "interestingAccounts"):
            guard
                let json = url.parseQueryString()["data"]?.first,
                let jsonData = json.data(using: .utf8),
                let dataAny = try? JSONSerialization.jsonObject(with: jsonData),
                let data = dataAny as? DataType,
                let accountIds = data["ids"] as? [Int64]
                else { return false }
            SettingsManager.addInterestingAccounts(ids: accountIds)
        case ("reactioncam", "show"):
            if
                url.lastPathComponent == "video",
                let address = url.parseQueryString()["url"]?.first,
                let url = URL(string: address)
            {
                Logging.log("Imported Video", ["URL": url.absoluteString])
                TabBarController.showCreate(url: url, source: "Imported Video")
            }
        case ("reactioncam", "tag"):
            TabBarController.select(tags: [url.lastPathComponent])
        case ("reactioncam", "user"):
            let identifier = url.lastPathComponent
            Intent.getProfile(identifier: identifier).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    return
                }
                TabBarController.select(account: Profile(data: data))
            }
        default:
            NSLog("%@", "WARNING: Unhandled URL: \(url)")
        }
        return false
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        Crashlytics.sharedInstance().delegate = self
        Fabric.with([Crashlytics.self])
        FirebaseApp.configure()

        // Set up Facebook SDK.
        FBSDKAppEvents.activateApp()
        FBSDKApplicationDelegate.sharedInstance().application(application, didFinishLaunchingWithOptions: launchOptions)

        // Set up Twitter SDK
        TWTRTwitter.sharedInstance().start(withConsumerKey: "_REMOVED_", consumerSecret: "_REMOVED_")

        // Set up Tumblr SDK
        if let client = TMAPIClient.sharedInstance() {
            client.oAuthConsumerKey = "_REMOVED_"
            client.oAuthConsumerSecret = "_REMOVED_"
            client.oAuthToken = SettingsManager.tumblrOAuthToken
            client.oAuthTokenSecret = SettingsManager.tumblrOAuthTokenSecret
        }

        // Set up event listeners.
        BackendClient.api.loggedIn.addListener(self, method: AppDelegate.handleLoggedIn)
        BackendClient.api.loggedOut.addListener(self, method: AppDelegate.handleLoggedOut)
        UploadService.instance.backgroundEventsCompleted.addListener(self, method: AppDelegate.handleBackgroundEventsCompleted)

        NotificationCenter.default.addObserver(forName: .UIApplicationUserDidTakeScreenshot, object: nil, queue: .main) { _ in
            Logging.info("Screenshot Taken")
        }

        // Set up notifications.
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        // Set up background fetch.
        application.setMinimumBackgroundFetchInterval(1800)

        SKPaymentQueue.default().add(PaymentService.instance)
        // TODO: Decide if we should only load products on demand instead.
        PaymentService.instance.loadProducts()

        self.setupIRate()
        SettingsManager.loadRecentAccounts()
        if BackendClient.api.session != nil {
            FollowService.instance.loadFollowing()
        }

        Logging.info("App Launched", ["LoggedIn": BackendClient.api.session != nil])

        // Take the user to the right place depending on their session.
        if let session = BackendClient.api.session {
            Crashlytics.sharedInstance().setUserIdentifier(String(session.id))
            if !session.hasService(id: "facebook") || session.hasBeenOnboarded {
                self.setRootViewController("RootNavigation")
            } else {
                self.setRootViewController("SetUsername")
            }
            self.checkPasteboard()
        } else {
            // Start a timer that will abort the deep link decoration flow.
            self.deepLinkTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                self.deepLinkTimer = nil
                Logging.warning("Deep Link Error", ["Error": "Decorating deep link timed out", "Result": "N/A"])
                self.setRootViewController("Landing")
            }
            // Try to use clipboard link as a reaction URL and fetch its metadata.
            let deepLinkURL: URL?
            if let url = UIPasteboard.general.url, AppDelegate.handleDeepLink(url, callback: self.decorateDeepLink) {
                deepLinkURL = url
                UIPasteboard.general.setValue("", forPasteboardType: UIPasteboardName.general.rawValue)
                // Take over launch screen while deep link is being decorated.
                // TODO: Fix status bar showing.
                self.displayLaunchScreen()
            } else {
                // Abort timer again since it won't be used.
                self.deepLinkTimer?.invalidate()
                self.deepLinkTimer = nil
                // Go through onboarding without deep linking.
                deepLinkURL = nil
                self.setRootViewController("Landing")
            }
            Logging.info("Onboarding Initiated", ["DeepLink": deepLinkURL?.absoluteString ?? "N/A"])
        }

        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        switch identifier {
        case BackendClient.api.backgroundManager.session.configuration.identifier!:
            BackendClient.api.backgroundManager.backgroundCompletionHandler = completionHandler
        case BackendClient.upload.backgroundManager.session.configuration.identifier!:
            BackendClient.upload.backgroundManager.backgroundCompletionHandler = completionHandler
        case UploadService.instance.session.configuration.identifier!:
            self.backgroundEventsCompletionHandler = completionHandler
        default:
            NSLog("%@", "WARNING: Ignoring handling background events for unknown identifier \(identifier)")
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppDelegate.applicationActiveStateChanged.emit(true)

        // Claim audio session.
        AudioService.instance.updateRoutes()

        Logging.debug("App Active", [
            "AudioRoute": AVAudioSession.sharedInstance().currentRoute.shortDescription,
            "BatteryLevel": AppDelegate.getBatteryLevel() * 100])

        ContentService.instance.loadFeaturedContent()

        guard let session = BackendClient.api.session else {
            // Nothing more to do if we're not logged in.
            return
        }

        self.checkPasteboard()
        self.updateServices()

        if Date() > session.expires, let token = session.refreshToken {
            // The access token expired, so refresh it.
            // TODO: This also needs to happen automatically when the token is about to expire.
            // TODO: Refresh session logic should be moved into BackendClient.
            Intent.refreshSession(refreshToken: token).perform(BackendClient.api)
        } else {
            Intent.getOwnProfile().perform(BackendClient.api)
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Logging.debug("App Inactive", ["BatteryLevel": AppDelegate.getBatteryLevel() * 100])
        AppDelegate.applicationActiveStateChanged.emit(false)
        
        if !UploadService.instance.jobs.isEmpty {
            let content = UNMutableNotificationContent()
            content.body = "⚠️ Keep the app open to ensure your uploads finish"
            content.categoryIdentifier = "cam.reaction.uploadWarningNotification"
            content.userInfo["api_version"] = 50
            content.userInfo["type"] = "upload-warning"
            let notif = UNNotificationRequest(identifier: "UploadWarning", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
            UNUserNotificationCenter.current().add(notif, withCompletionHandler: nil)
        }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // TODO: Handle background push notifications.
        guard let event = self.parse(userInfo: userInfo, source: "application:didReceiveRemoteNotification") else {
            completionHandler(.failed)
            return
        }
        self.handle(event: event) {
            switch $0 {
            case .invalidData:
                NSLog("WARNING: Failed to handle \(event.type) event")
                completionHandler(.failed)
            default:
                completionHandler(.newData)
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        self.notificationToken = deviceToken.hex
        self.putNotificationToken()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("%@", "WARNING: Failed to register for remote notifications: \(error)")
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard BackendClient.api.session != nil else {
            completionHandler(.noData)
            return
        }
        // TODO: Do more clever stuff here.
        NotificationService.instance.loadNotificationsForced { _ in
            completionHandler(.newData)
        }
    }

    // MARK: - iRateDelegate

    func iRateShouldPromptForRating() -> Bool {
        return false
    }

    func iRateDidOpenAppStore() {
        Logging.log("iRate Event", ["Event": "OpenAppStore"])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard let event = self.parse(notification: notification, source: "userNotificationCenter:willPresent") else {
            completionHandler([.alert, .badge, .sound])
            return
        }
        Logging.debug("System Notification Shown", ["Type": event.type])
        self.handle(event: event) {
            let topVC = TabBarController.instance?.navigationController?.topViewController
            guard !(topVC is CreationViewController) else {
                AppDelegate.notifsSquelched += 1
                completionHandler([.badge])
                return
            }
            switch $0 {
            case let .chatChannel(channelId):
                if let vc = topVC as? ProfileViewController, vc.isShowing(channel: channelId) {
                    completionHandler([.badge])
                } else {
                    completionHandler([.alert, .badge, .sound])
                    AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
                }
            case .contentComment, .notificationScreenUpdate, .openURL:
                completionHandler([.alert, .badge, .sound])
                AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
            case let .threadMessage(thread):
                if let vc = topVC as? MessagesViewController, vc.thread.id == thread.id {
                    completionHandler([.badge])
                } else {
                    completionHandler([.alert, .badge, .sound])
                }
            default:
                completionHandler([.alert, .badge, .sound])
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let event = self.parse(notification: response.notification, source: "userNotificationCenter:didReceive") else {
            completionHandler()
            return
        }
        Logging.log("System Notification Selected", [
            "Action": response.actionIdentifier,
            "Type": event.type])
        self.handle(event: event) {
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                switch $0 {
                case let .chatChannel(channelId):
                    Intent.getProfile(identifier: channelId).perform(BackendClient.api) {
                        guard $0.successful, let data = $0.data else {
                            return
                        }
                        TabBarController.select(account: Profile(data: data), showChat: true)
                    }
                case let .content(content):
                    TabBarController.select(contentId: content.id)
                case let .contentComment(content, comment):
                    if comment.offset >= 0 {
                        let offset = max(Double(comment.offset - 500) / 1000, 0)
                        TabBarController.select(contentId: content.id, offset: offset)
                    } else {
                        TabBarController.select(originalContent: content, inject: nil, tab: .comments, animated: true,
                                                source: "Comment System Notif")
                    }
                case .invalidData, .other:
                    break
                case .notificationScreenUpdate:
                    TabBarController.select(tab: .notifications, source: "Notification")
                case let .openURL(url):
                    UIApplication.shared.open(url)
                case let .threadMessage(thread):
                    TabBarController.select(thread: thread)
                }
            }
            completionHandler()
        }
    }

    // MARK: - Private

    private static var notifsSquelched = 0
    private static var pendingDeepLinkResult: DeepLinkResult?
    private static var queuedLogIntents = [Intent]()

    private var backgroundEventsCompletionHandler: (() -> ())?
    private var deepLinkTimer: Timer?
    private var notificationToken: String?

    private func checkPasteboard() {
        guard let url = UIPasteboard.general.url, url.fragment == "react" else {
            return
        }
        if AppDelegate.handleDeepLink(url: url) {
            SetDemoViewController.shouldAskLater = true
        }
        UIPasteboard.general.setValue("", forPasteboardType: UIPasteboardName.general.rawValue)
    }

    private func decorateDeepLink(_ result: DeepLinkResult) {
        AppDelegate.pendingDeepLinkResult = result
        guard self.deepLinkTimer != nil else { return }
        let error = { (error: String) in
            Logging.warning("Deep Link Error", [
                "Error": error,
                "Result": String(describing: result)])
            self.setRootViewController("Landing")
        }
        guard case let .content(content, react) = result, react else {
            error("Link did not resolve to reactable content")
            return
        }
        guard let thumbURL = content.thumbnailURL else {
            error("Resolved content did not have a thumbnail")
            return
        }
        ImageDownloader.default.download(URLRequest(url: thumbURL)) {
            guard let timer = self.deepLinkTimer else { return }
            timer.invalidate()
            self.deepLinkTimer = nil
            guard let image = $0.result.value else {
                error("Could not load image")
                return
            }
            Logging.info("Deep Link Decorated", ["ContentId": content.id])
            let vc = self.storyboard.instantiateViewController(withIdentifier: "Landing") as! LandingViewController
            vc.backgroundImage = image
            vc.deepLinkedContent = content
            self.window!.rootViewController = vc
        }
    }

    private func displayLaunchScreen() {
        let storyboard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        let launchVC = storyboard.instantiateViewController(withIdentifier: "launch")
        self.window!.rootViewController = launchVC
    }

    private func handle(event: NotificationEvent, callback: ((NotificationEventResult) -> ())? = nil) {
        switch event.type {
        case "account-change":
            guard let data = event.data["account"] as? DataType else {
                callback?(.invalidData)
                return
            }
            if let status = data["status"] as? String, status == "banned" {
                SettingsManager.isTainted = true
                BackendClient.api.session = nil
                callback?(.other)
                return
            }
            BackendClient.api.updateAccountData(data)
            callback?(.other)
        case "account-follow", "friend-joined":
            NotificationService.instance.loadNotificationsForced()
            callback?(.notificationScreenUpdate)
        case "chat-join", "chat-mention", "chat-message", "chat-owner-join":
            guard let channelId = event.data["channel_id"] as? String else {
                callback?(.invalidData)
                return
            }
            callback?(.chatChannel(channelId))
        case "content-comment":
            NotificationService.instance.loadNotificationsForced()
            guard
                let contentData = event.data["content"] as? DataType,
                let content = ContentInfo(data: contentData),
                let commentData = event.data["comment"] as? DataType,
                let accountData = event.data["commenter"] as? DataType
                else
            {
                callback?(.invalidData)
                return
            }
            let comment = Comment(comment: commentData, account: accountData)
            callback?(.contentComment(content, comment))
        case "content-created", "content-mention", "content-view", "content-vote":
            if event.type == "content-view" {
                NotificationService.instance.loadNotifications()
            } else {
                NotificationService.instance.loadNotificationsForced()
            }
            guard let content = Content(data: event.data) else {
                callback?(.invalidData)
                return
            }
            ContentService.instance.contentUpdated.emit(content)
            callback?(.content(content))
        case "content-featured", "content-referenced", "content-request", "content-request-fulfilled", "streak":
            NotificationService.instance.loadNotificationsForced()
            callback?(.notificationScreenUpdate)
        case "custom":
            if let url = (event.data["alert_open_url"] as? String).flatMap(URL.init(string:)) {
                callback?(.openURL(url))
            } else if (event.data["notif_disabled"] as? Bool) ?? false {
                callback?(.other)
            } else {
                NotificationService.instance.loadNotificationsForced()
                callback?(.notificationScreenUpdate)
            }
        case "public-request-update":
            guard let requestId = event.data["request_id"] as? Int64 else {
                callback?(.invalidData)
                return
            }
            // TODO: We may want to show these updates as system notifications too.
            TabBarController.instance?.navigationController?.viewControllers
                .compactMap { $0 as? PublicRequestViewController }
                .filter { $0.info.request.id == requestId }
                .forEach { $0.reloadData() }
            callback?(.other)
        case "squelched-notifs":
            TabBarController.select(tab: .notifications, source: "SquelchedNotifs")
        case "thread-message":
            guard
                let threadData = event.data["thread"] as? DataType,
                let messageData = event.data["message"] as? DataType,
                let thread = try? MessageService.instance.update(threadData: threadData, messageData: [messageData])
                else
            {
                callback?(.invalidData)
                return
            }
            callback?(.threadMessage(thread))
        default:
            NSLog("%@", "WARNING: Unhandled notification type: \(event.type)")
            callback?(.invalidData)
        }
    }

    private func handleBackgroundEventsCompleted() {
        self.backgroundEventsCompletionHandler?()
    }

    /// Parse the type and data of the push notification, validating everything along the way.
    private func parse(notification: UNNotification, source: String? = nil) -> NotificationEvent? {
        return self.parse(userInfo: notification.request.content.userInfo, source: source)
    }

    /// Parse the type and data of the push notification, validating everything along the way.
    private func parse(userInfo: [AnyHashable: Any], source: String? = nil) -> NotificationEvent? {
        // Every push notification should contain a type, a version and some data.
        guard let type = userInfo["type"] as? String else {
            Logging.danger("Notification Parse Error", [
                "Data": userInfo.debugDescription,
                "Source": source ?? "N/A"])
            NSLog("%@", "WARNING: Failed to get type of notification\n\(userInfo)")
            return nil
        }
        guard BackendClient.api.session != nil else {
            NSLog("%@", "WARNING: Ignoring \(type) notification (no session)\n\(userInfo)")
            return nil
        }
        guard let version = userInfo["api_version"] as? Int, version >= 43 else {
            NSLog("%@", "WARNING: Incompatible notification version\n\(userInfo)")
            return nil
        }
        var data = [String: Any]()
        for (key, value) in userInfo {
            guard let key = key as? String else {
                continue
            }
            // Skip the non-data keys.
            if key == "api_version" || key == "aps" || key == "type" {
                continue
            }
            data[key] = value
        }
        return NotificationEvent(type: type, data: data)
    }

    private func putNotificationToken() {
        guard BackendClient.api.session != nil, let token = self.notificationToken else {
            return
        }
        let intent = Intent.registerDeviceForPush(
            deviceId: UIDevice.current.identifierForVendor?.uuidString,
            environment: Bundle.main.apsEnvironment,
            platform: "ios",
            token: token)
        intent.performWithoutDispatch(BackendClient.api) {
            if !$0.successful, let error = $0.error {
                NSLog("%@", "WARNING: Failed to store device token in backend: \(error)")
            }
        }
    }

    private func setRootViewController(_ identifier: String) {
        self.window!.rootViewController = self.storyboard.instantiateViewController(withIdentifier: identifier)
    }

    private func setupIRate() {
        guard let rate = iRate.sharedInstance() else {
            return
        }
        rate.appStoreID = 1225620956
        rate.daysUntilPrompt = 0
        rate.usesUntilPrompt = 0
        rate.eventsUntilPrompt = 3
        rate.delegate = self
        rate.promptForNewVersionIfUserRated = false
    }

    // MARK: - Events

    private func handleLoggedIn(session: Session) {
        self.putNotificationToken()
        let intents = AppDelegate.queuedLogIntents
        AppDelegate.queuedLogIntents.removeAll()
        for intent in intents {
            intent.perform(BackendClient.api)
        }
        Crashlytics.sharedInstance().setUserIdentifier(String(session.id))
        SettingsManager.autopostYouTube = session.hasService(id: "youtube")
        self.updateServices()
    }

    private func handleLoggedOut() {
        // Make sure to disconnect everything that depends on session.
        FBSDKLoginManager().logOut()
        ChatService.instance.disconnect()

        guard let window = self.window else {
            return
        }
        let landing = self.storyboard.instantiateViewController(withIdentifier: "Landing")
        landing.modalTransitionStyle = .flipHorizontal
        window.rootViewController?.dismiss(animated: false)
        window.rootViewController?.present(landing, animated: true)
    }

    private func updateServices() {
        MessageService.instance.loadThreads()
        NotificationService.instance.loadNotifications()
    }
}
