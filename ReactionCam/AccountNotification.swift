import Foundation

struct AccountNotification {
    let data: DataType

    let groupCount: Int
    let groupHistory: [[String: Any]]
    let id: Int64
    let seen: Bool
    let timestamp: Date
    let type: String
    let properties: [String: Any]

    var shouldAutoMarkAsSeen: Bool {
        guard !self.seen else {
            return false
        }
        switch self.type {
        case "content-featured", "content-request", "content-request-fulfilled", "friend-joined", "update-app":
            return false
        case "custom":
            return (self.properties["auto_mark_seen"] as? Bool) ?? true
        default:
            return true
        }
    }

    static let supportedTypes = [
        "account-follow",
        "chat-mention",
        "chat-message",
        "chat-join",
        "chat-owner-join",
        "coins-received",
        "content-comment",
        "content-created",
        "content-featured",
        "content-mention",
        "content-referenced",
        "content-request",
        "content-request-fulfilled",
        "content-vote",
        "custom",
        "friend-joined",
        "streak",
        "update-app",
    ]

    init?(data: DataType) {
        var properties = data
        guard
            let id = properties.removeValue(forKey: "id") as? Int64,
            let type = properties.removeValue(forKey: "type") as? String,
            AccountNotification.supportedTypes.contains(type)
            else { return nil }
        self.data = data
        self.groupCount = properties.removeValue(forKey: "group_count") as! Int
        self.groupHistory = properties.removeValue(forKey: "group_history") as! [[String: Any]]
        self.id = id
        self.type = type
        self.seen = properties.removeValue(forKey: "seen") as! Bool
        let timestamp = properties.removeValue(forKey: "timestamp") as! Int64
        self.timestamp = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        self.properties = properties
    }
}
