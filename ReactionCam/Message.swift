import Foundation

struct Message {
    enum MessageType: String {
        case currency
        case request
        case text
        case unknown
    }

    let id: String
    let accountId: Int64
    let data: DataType
    let parentId: String
    let text: String
    let timestamp: Date
    let type: MessageType

    init(channelId: String, senderId: Int64, data: DataType) throws {
        guard let text = data["text"] as? String else {
            throw MessageServiceError.invalidData
        }
        try self.init(
            parentId: channelId,
            senderId: senderId,
            text: text,
            timestamp: (data["timestamp"] as? Double).flatMap({ Date(timeIntervalSince1970: $0 / 1000) }) ?? Date(),
            type: (data["type"] as? String).flatMap({ MessageType(rawValue: $0) }) ?? .text,
            data: data["data"] as? DataType ?? [:])
    }

    init(threadId: String, data: DataType) throws {
        guard
            let accountId = data["account_id"] as? Int64,
            let created = data["created"] as? Double,
            let messageData = data["data"] as? DataType,
            let id = data["id"] as? String,
            let text = data["text"] as? String,
            let type = data["type"] as? String
            else { throw MessageServiceError.invalidData }
        try self.init(
            parentId: threadId,
            id: id,
            senderId: accountId,
            text: text,
            timestamp: Date(timeIntervalSince1970: created / 1000),
            type: MessageType(rawValue: type) ?? .text,
            data: messageData)
    }

    init(parentId: String, id: String? = nil, senderId: Int64? = nil, text: String, timestamp: Date? = nil, type: MessageType = .text, data: DataType = [:]) throws {
        guard type != .unknown else {
            throw MessageServiceError.invalidType
        }
        self.parentId = parentId
        if let id = senderId {
            self.accountId = id
        } else if let session = BackendClient.api.session {
            self.accountId = session.id
        } else {
            throw MessageServiceError.missingSession
        }
        self.timestamp = timestamp ?? Date()
        if let id = id {
            self.id = id
        } else {
            let ms = Int64(self.timestamp.timeIntervalSince1970 * 1000)
            self.id = "\(ms)_\(self.accountId)_local"
        }
        self.data = data
        self.text = text
        self.type = type
    }
}
