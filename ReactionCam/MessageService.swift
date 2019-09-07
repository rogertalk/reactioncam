import Foundation

class MessageService {
    typealias ThreadsDict = OrderedDictionary<String, MessageThread>
    typealias ThreadsDiff = ThreadsDict.Difference

    static let instance = MessageService()

    let messageReceived = Event2<MessageThread, Message>()
    let threadsChanged = Event2<[MessageThread], ThreadsDiff>()
    let threadUpdated = Event<MessageThread>()

    private(set) var threads = ThreadsDict() {
        didSet {
            TabBarController.updateBadgeNumber()

            // Calculate a difference and potentially notify interested parties.
            let diff = oldValue.diff(self.threads)
            guard !diff.deleted.isEmpty || !diff.inserted.isEmpty || !diff.moved.isEmpty else {
                // The list of threads didn't change (note that individual threads may still have changed).
                return
            }
            self.threadsChanged.emit(self.threads.values, diff)
        }
    }
    
    var unseenCount: Int {
        return self.threads.values.reduce(0, { $0 + ($1.seen ? 0 : 1) })
    }

    func createThread(identifier: String, callback: @escaping (MessageThread?, Error?) -> ()) {
        Intent.getOrCreateThread(identifier: identifier).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data else {
                callback(nil, $0.error)
                return
            }
            callback(try! MessageThread(data: data), nil)
        }
    }

    func hide(thread: MessageThread, callback: ((Bool) -> ())? = nil) {
        Intent.updateThreadVisibility(threadId: thread.id, visible: false).perform(BackendClient.api) {
            guard $0.successful else {
                callback?(false)
                return
            }
            self.threads.removeValue(forKey: thread.id)
            callback?(true)
        }
    }

    func loadMessages(for thread: MessageThread, cursor: String? = nil, callback: ((String?) -> ())? = nil) {
        Intent.getThreadMessages(threadId: thread.id, cursor: cursor).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                callback?(nil)
                return
            }
            _ = try? self.update(threadData: thread.data, messageData: data)
            callback?($0.data?["cursor"] as? String)
        }
    }

    func loadThreads(page: Bool = false, callback: ((Bool) -> ())? = nil) {
        // TODO: Don't overload method with variable.
        // TODO: Fix thread race conditions below.
        guard !self.isLoadingThreads else {
            callback?(false)
            return
        }
        // If not paging, load from scratch. Otherwise, ensure cursor is valid.
        if !page {
            self.cursor = nil
        } else if self.cursor == nil {
            callback?(false)
            return
        }
        self.isLoadingThreads = true
        Intent.getThreads(cursor: self.cursor).perform(BackendClient.api) {
            self.isLoadingThreads = false
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                callback?(false)
                return
            }
            let threads = data.compactMap { try? MessageThread(data: $0) }
            let threadsDict = ThreadsDict(threads.map { ($0.id, $0) })
            if page {
                self.threads.append(contentsOf: threadsDict)
            } else {
                self.threads = threadsDict
            }
            self.cursor = $0.data?["cursor"] as? String
            callback?(true)
        }
    }

    func markSeen(thread: MessageThread) {
        guard !thread.seen, let messageId = thread.messages.first?.value.id else {
            return
        }
        // Locally update the thread to be seen.
        var newData = thread.data
        newData["seen_until"] = messageId
        try! self.update(threadData: newData)
        Intent.updateThreadSeenUntil(threadId: thread.id, messageId: messageId).perform(BackendClient.api)
    }

    func message(thread: MessageThread, type: Message.MessageType, text: String, data: DataType? = nil, callback: ((Bool) -> ())? = nil) {
        Intent.messageThread(threadId: thread.id, type: type.rawValue, text: text, data: data).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data else {
                callback?(false)
                return
            }
            callback?(true)
            try! self.update(threadData: data)
        }
    }

    func show(thread: MessageThread, callback: ((Bool) -> ())? = nil) {
        Intent.updateThreadVisibility(threadId: thread.id, visible: true).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data else {
                callback?(false)
                return
            }
            try! self.update(threadData: data)
            callback?(true)
        }
    }

    @discardableResult
    func update(threadData: DataType, messageData: [DataType] = []) throws -> MessageThread {
        var threads = self.threads
        let threadId = threadData["id"] as! String
        let thread = try MessageThread(data: threadData, basedOn: threads[threadId])
        if !messageData.isEmpty {
            try thread.add(messages: messageData.map { try Message(threadId: threadId, data: $0) })
        }
        threads[threadId] = thread
        self.threads = ThreadsDict(threads.sorted(by: {
            $0.value.lastInteraction > $1.value.lastInteraction
        }))
        self.threadUpdated.emit(thread)
        return thread
    }

    // MARK: - Private

    private var cursor: String? = nil
    private var isLoadingThreads = false

    private init() {
    }
}
