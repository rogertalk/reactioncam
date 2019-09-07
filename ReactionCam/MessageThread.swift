import Foundation

class MessageThread {
    typealias MessagesDict = OrderedDictionary<String, Message>
    typealias MessagesDiff = MessagesDict.Difference

    let data: DataType
    let id: String
    let created: Date
    let lastInteraction: Date
    let seenUntil: String?
    
    private(set) var messages = MessagesDict()
    private(set) var others: [ThreadAccount]

    var seen: Bool {
        return self.messages.first?.value.id == self.seenUntil
    }

    var imageURL: URL? {
        guard let account = self.others.first else {
            return BackendClient.api.session?.imageURL
        }
        return account.imageURL
    }

    var title: String {
        return self.others.map({ "@\($0.username)" }).joined(separator: ", ")
    }
    
    init(data: DataType, basedOn otherThread: MessageThread? = nil) throws {
        self.data = data
        let id = data["id"] as! String
        self.id = id
        self.created = Date(timeIntervalSince1970: (data["created"] as! Double) / 1000)
        self.lastInteraction = Date(timeIntervalSince1970: (data["last_interaction"] as! Double) / 1000)
        if let messagesData = data["messages"] as? [DataType] {
            let messages = try messagesData.map { try Message(threadId: id, data: $0) }
            self.messages = MessagesDict(messages.map { ($0.id, $0) })
        }
        self.others = (data["others"] as! [DataType]).map { ThreadAccount(data: $0) }
        self.seenUntil = data["seen_until"] as? String
        if let thread = otherThread {
            guard id == thread.id else {
                throw MessageServiceError.threadIdMismatch
            }
            try self.add(messages: thread.messages.values)
        }
    }

    func account(id: Int64) -> ThreadAccount {
        guard let account = self.others.first(where: { $0.id == id }) else {
            return ThreadAccount(id: id)
        }
        return account
    }

    func add(messages list: [Message]) throws {
        var messages = self.messages
        for message in list {
            guard message.parentId == self.id else {
                throw MessageServiceError.threadIdMismatch
            }
            messages[message.id] = message
        }
        self.messages = MessagesDict(messages.sorted { $0.value.timestamp > $1.value.timestamp })
    }

    func hide() {
        MessageService.instance.hide(thread: self)
    }

    @discardableResult
    func message(type: Message.MessageType, text: String, data: DataType? = nil) throws -> Message {
        let message = try Message(parentId: self.id, text: text, type: type, data: data ?? [:])
        try self.add(messages: [message])
        MessageService.instance.message(thread: self, type: type, text: text, data: data) { _ in
            // TODO: Update local message state to reflect success/failure.
            _ = self.messages.removeValue(forKey: message.id)
        }
        return message
    }
}

extension MessageThread: Equatable {
    public static func ==(lhs: MessageThread, rhs: MessageThread) -> Bool {
        return lhs.id == rhs.id
    }
}
