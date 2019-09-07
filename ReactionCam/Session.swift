import CloudKit
import Foundation

private let currentSessionVersion = 4

private func getAccountId(_ data: DataType) -> Int64? {
    guard let account = data["account"] as? DataType, let id = account["id"] as? NSNumber else {
        return nil
    }
    return id.int64Value
}

struct Session: AccountWithExtras {
    struct Service {
        let id: String
        let team: String?
        let resource: String

        init?(identifier: String) {
            let idResource = identifier.split(separator: ":", maxSplits: 1)
            guard idResource.count == 2 else {
                return nil
            }
            self.id = String(idResource[0])
            let teamResource = idResource[1].split(separator: "/", maxSplits: 1)
            let resourceEncoded: String
            if teamResource.count == 2 {
                self.team = teamResource[0].removingPercentEncoding
                resourceEncoded = String(teamResource[1])
            } else {
                self.team = nil
                resourceEncoded = String(idResource[1])
            }
            guard let resource = resourceEncoded.removingPercentEncoding else {
                return nil
            }
            self.resource = resource
        }
    }

    struct YouTubeChannel {
        let id: String
        let thumbURL: URL?
        let title: String

        init?(data: DataType) {
            guard
                let id = data["id"] as? String,
                let title = data["title"] as? String
                else { return nil }
            self.id = id
            self.thumbURL = (data["thumb_url"] as? String).flatMap(URL.init(string:))
            self.title = title
        }
    }

    let account: [String: Any]
    let data: DataType
    let id: Int64
    let identifiers: [String]
    let services: [Service]
    let youTubeChannel: YouTubeChannel?

    var accessToken: String {
        return self.data["access_token"] as! String
    }

    var balance: Int {
        return self.account["balance"] as? Int ?? 0
    }

    var birthday: Date? {
        guard let dateString = self.account["birthday"] as? String else {
            return nil
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dateString)
    }

    var bonusBalance: Int {
        return self.account["bonus"] as? Int ?? 0
    }

    var contentCount: Int {
        return self.account["content_count"] as? Int ?? 0
    }

    var didSetDisplayName: Bool {
        return self.account["display_name_set"] as? Bool ?? true
    }

    var displayName: String {
        return self.account["display_name"] as! String
    }

    var email: String? {
        guard
            let service = self.services.first(where: { $0.id == "email" }),
            let team = service.team
            else { return nil }
        return "\(service.resource)@\(team)"
    }

    var expires: Date {
        let ttl = (self.data["expires_in"] as! NSNumber).intValue
        return Date(timeIntervalSinceNow: TimeInterval(ttl))
    }

    var followerCount: Int {
        return self.account["follower_count"] as? Int ?? 0
    }

    var followingCount: Int {
        return self.account["following_count"] as? Int ?? 0
    }

    var gender: Intent.Gender? {
        return (self.account["gender"] as? String).flatMap { Intent.Gender(rawValue: $0) }
    }

    var hasBeenOnboarded: Bool {
        return (self.account["onboarded"] as? Bool) ?? false
    }

    var hasRewards: Bool {
        return self.account["has_reward"] as? Bool ?? false
    }

    var imageURL: URL? {
        return (self.account["image_url"] as? String).flatMap(URL.init(string:))
    }

    var isActive: Bool {
        return self.data["status"] as! String == "active"
    }

    var isBlocked: Bool {
        return false
    }

    var isVerified: Bool {
        return self.account["verified"] as? Bool ?? false
    }

    var premiumProperties: [String] {
        return self.account["premium_properties"] as? [String] ?? []
    }

    var properties: [String: Any] {
        return self.account["properties"] as? [String: Any] ?? [:]
    }

    var refreshToken: String? {
        return self.data["refresh_token"] as? String
    }

    var status: String {
        return self.data["status"] as! String
    }

    let timestamp: Date

    var username: String {
        return self.account["username"] as! String
    }

    static func clear() {
        NSUbiquitousKeyValueStore.default.removeObject(forKey: "session")
        if let url = self.sessionSaveURL {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                NSLog("%@", "WARNING: Failed to clear session file")
            }
        }
    }

    static func load() -> Session? {
        guard
            let url = self.sessionSaveURL, let archivedData = try? Data(contentsOf: url),
            let dict = NSKeyedUnarchiver.unarchiveObject(with: archivedData) as? DataType
            else { return self.fromUbiquitousStore() }
        return self.fromVersionedData(dict)
    }

    init?(_ data: DataType, timestamp: Date) {
        self.data = data
        guard let id = getAccountId(data) else {
            self.id = -1
            return nil
        }
        self.id = id
        let account = data["account"] as! DataType
        self.account = account
        let identifiers = account["identifiers"] as? [String] ?? []
        self.identifiers = identifiers
        self.services = identifiers.compactMap(Service.init(identifier:))
        self.timestamp = timestamp
        self.youTubeChannel = (account["youtube"] as? DataType).flatMap(YouTubeChannel.init(data:))
    }

    func hasService(id: String) -> Bool {
        return self.services.contains(where: { $0.id == id })
    }

    func hasService(id: String, resource: String) -> Bool {
        return self.services.contains(where: { $0.id == id && $0.resource == resource })
    }

    func save() throws {
        var url = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        url.appendPathComponent("Session.bin")
        var dict: [String: Any] = [
            "data": self.data,
            "refresh_token": self.refreshToken ?? NSNull(),
            "timestamp": self.timestamp.timeIntervalSince1970,
            "version": currentSessionVersion,
        ]
        dict["refresh_token"] = self.refreshToken
        let data = NSKeyedArchiver.archivedData(withRootObject: dict)
        try data.write(to: url, options: [.atomic])
        // Also store the session in iCloud.
        let store = NSUbiquitousKeyValueStore.default
        store.set(data, forKey: "session")
        store.synchronize()
    }

    func withNewAccountData(_ accountData: DataType) -> Session? {
        var data = self.data
        data["account"] = accountData
        return Session(data, timestamp: self.timestamp)
    }

    // MARK: - Private

    private static var sessionSaveURL: URL? {
        guard let dir = try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        return dir.appendingPathComponent("Session.bin")
    }

    private static func fromUbiquitousStore() -> Session? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard
            let data = store.data(forKey: "session"),
            let dict = NSKeyedUnarchiver.unarchiveObject(with: data) as? DataType
            else { return nil }
        return self.fromVersionedData(dict)
    }

    private static func fromVersionedData(_ dict: DataType) -> Session? {
        guard let data = dict["data"] as? DataType else {
            return nil
        }
        let timestamp = (dict["timestamp"] as? Date) ?? Date()
        let version = (dict["version"] as? Int) ?? 0
        // Ensure the session is of a compatible version or upgrade it.
        switch version {
        case currentSessionVersion:
            return Session(data, timestamp: timestamp)
        default:
            NSLog("%@", "WARNING: Tried to load session with unsupported version \(version)")
            return nil
        }
    }
}
