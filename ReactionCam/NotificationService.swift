import UIKit

class NotificationService {
    static let instance = NotificationService()

    let notifsChanged = Event<Void>()

    private(set) var notifs = [AccountNotification]() {
        didSet {
            TabBarController.updateBadgeNumber()
            self.notifsChanged.emit()
        }
    }

    var unseenCount: Int {
        return self.notifs.reduce(0, { $0 + ($1.seen ? 0 : 1) })
    }

    @discardableResult
    func loadNotifications() -> Bool {
        guard
            BackendClient.api.session != nil,
            Date().timeIntervalSince(self.lastLoad) > 10
            else { return false }
        self.loadNotificationsForced()
        return true
    }

    func loadNotificationsForced(callback: ((Bool) -> ())? = nil) {
        assert(BackendClient.api.session != nil, "Cannot load notifications without a session")
        self.lastLoad = Date()
        Intent.getNotifications().perform(BackendClient.api) {
            guard $0.successful, let notifsData = $0.data?["data"] as? [DataType] else {
                callback?(false)
                return
            }
            self.notifs = notifsData.compactMap(AccountNotification.init(data:))
            callback?(true)
        }
    }

    func markSeen(notif: AccountNotification) {
        guard !notif.seen else {
            return
        }
        // Locally update the notification to be seen.
        var newData = notif.data
        newData["seen"] = NSNumber(value: true)
        if let newNotif = AccountNotification(data: newData) {
            var notifs = self.notifs
            for i in 0..<notifs.count {
                if notifs[i].id == newNotif.id {
                    notifs[i] = newNotif
                    break
                }
            }
            self.notifs = notifs
        }
        guard notif.id > 0 else {
            // Some fake notifications may have an invalid id.
            return
        }
        Intent.markNotificationSeen(id: notif.id).perform(BackendClient.api)
    }

    // MARK: - Private

    private var lastLoad: Date = .distantPast

    private init() {
        BackendClient.api.loggedIn.addListener(self, method: NotificationService.handleLoggedIn)
        BackendClient.api.loggedOut.addListener(self, method: NotificationService.handleLoggedOut)
    }

    private func handleLoggedIn(session: Session) {
        self.notifs = []
        self.loadNotifications()
    }

    private func handleLoggedOut() {
        self.notifs = []
    }
}
