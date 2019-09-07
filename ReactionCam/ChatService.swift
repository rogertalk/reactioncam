import Foundation
import Starscream

private let BACKOFF_MIN: Double = 0.25
private let BACKOFF_MAX: Double = 32
private let BACKOFF_MUL: Double = 4

class ChatService: WebSocketDelegate {
    static let instance = ChatService()
    static let url = URL(string: "wss://chat.reaction.cam/v1/channel")!

    let connected = Event<Void>()
    let disconnected = Event<Void>()
    let joinedChannel = Event<Channel>()
    let leftChannel = Event<String>()
    let newMessage = Event2<Channel, Channel.Entry>()
    let participantsChanged = Event<Channel>()

    private(set) var channels = [String: Channel]()

    var isConnected: Bool {
        return self.socket.isConnected
    }

    func connect(session: Session) {
        self.queue.async {
            if session.id != self.session?.id {
                // Make sure to not reuse connection if the account changed.
                self.channels = [:]
                self.pendingMessages = []
                self.socket.disconnect()
            }
            self.autoReconnect = true
            self.session = session
            guard !self.socket.isConnected else {
                return
            }
            self.socket.connect()
        }
    }

    func disconnect() {
        self.queue.async {
            self.autoReconnect = false
            self.channels = [:]
            self.pendingMessages = []
            self.session = nil
            self.socket.disconnect()
        }
    }

    func join(channelId: String) {
        self.safelyWrite(command: "join", ["channel_id": channelId])
    }

    func kick(accountId: Int64, from channelId: String) {
        self.safelyWrite(command: "kick", ["account_id": accountId, "channel_id": channelId])
    }

    func leave(channelId: String) {
        self.safelyWrite(command: "leave", ["channel_id": channelId])
    }

    func send(to channelId: String, text: String) {
        if self.channels[channelId] == nil {
            self.join(channelId: channelId)
        }
        self.safelyWrite(command: "text", ["to": channelId, "text": text])
    }

    // MARK: - WebSocketDelegate

    func websocketDidConnect(socket: WebSocketClient) {
        self.backoff = BACKOFF_MIN
        guard let session = self.session else {
            NSLog("%@", "WARNING: Connected to chat server without a session")
            self.disconnect()
            return
        }
        guard let data = try? self.encode(command: "auth", ["access_token": session.accessToken]) else {
            NSLog("%@", "WARNING: Could not encode authentication command")
            self.disconnect()
            return
        }
        socket.write(data: data)
        self.connected.emit()
        print("--- Chat connected")
        // Send off any pending messages that were attempted while connecting.
        if !self.pendingMessages.isEmpty {
            for data in self.pendingMessages {
                socket.write(data: data)
            }
            self.pendingMessages = []
        }
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        self.channels = [:]
        self.disconnected.emit()
        if let error = error {
            print("--- Chat SHUTDOWN: \(error)")
        } else {
            print("--- Chat disconnected")
        }
        guard self.autoReconnect else {
            return
        }
        print("--- Reconnecting in \(self.backoff) seconds")
        self.queue.asyncAfter(deadline: .now() + self.backoff) {
            guard !self.socket.isConnected, self.autoReconnect else {
                return
            }
            self.socket.connect()
        }
        self.backoff = min(self.backoff * BACKOFF_MUL, BACKOFF_MAX)
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("--- Chat received data: \(String(data: data, encoding: .utf8) ?? data.debugDescription)")
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        guard let session = self.session else {
            NSLog("%@", "WARNING: Received message without a session: \(text)")
            return
        }
        let pieces = text.split(separator: " ", maxSplits: 2)
        guard
            pieces.count == 3,
            let senderId = Int64(pieces[0]),
            let dataRaw = pieces[2].data(using: .utf8),
            let dataAny = try? JSONSerialization.jsonObject(with: dataRaw),
            let data = dataAny as? DataType
            else
        {
            NSLog("%@", "WARNING: Failed to parse message: \(text)")
            return
        }
        let type = pieces[1]
        switch type {
        case "channel":
            guard
                let id = data["id"] as? String,
                let others = (data["others"] as? [DataType])?.compactMap(MessageAccount.init(data:)),
                let historyData = data["history"] as? [DataType]
                else
            {
                NSLog("%@", "WARNING: Invalid channel data: \(data)")
                break
            }
            if self.channels[id] != nil {
                NSLog("%@", "WARNING: Got channel info for known channel: \(data)")
                break
            }
            let history: [Channel.Entry] = historyData.compactMap {
                guard
                    let account = ($0["account"] as? DataType).flatMap(MessageAccount.init(data:)),
                    let message = try? Message(channelId: id, senderId: account.id, data: $0)
                    else { return nil }
                return Channel.Entry(account: account, message: message)
            }
            let me = MessageAccount(from: session)
            let channel = Channel(id: id, accounts: [me] + others, history: history)
            self.channels[id] = channel
            self.joinedChannel.emit(channel)
            print("--- Current user is in #\(channel.id)")
        case "join":
            guard
                let account = (data["account"] as? DataType).flatMap(MessageAccount.init(data:)),
                let channelId = data["channel_id"] as? String,
                let channel = self.channels[channelId]
                else
            {
                NSLog("%@", "WARNING: Got invalid join message: \(data)")
                break
            }
            channel.accounts[senderId] = account
            self.participantsChanged.emit(channel)
            print("--- @\(account.username) joined #\(channel.id)")
        case "kick":
            guard
                let accountId = data["account_id"] as? Int64,
                let channelId = data["channel_id"] as? String,
                let channel = self.channels[channelId],
                let account = channel.accounts[accountId]
                else
            {
                NSLog("%@", "WARNING: Got kick for unknown channel/account: \(data)")
                break
            }
            let kicker = channel.accounts[senderId]
            guard account.id != session.id else {
                self.channels.removeValue(forKey: channelId)
                self.leftChannel.emit(channelId)
                print("--- Current user was kicked from #\(channel.id) by @\(kicker?.username ?? "???")")
                break
            }
            if let account = channel.accounts.removeValue(forKey: accountId) {
                self.participantsChanged.emit(channel)
                print("--- @\(account.username) was kicked from #\(channel.id) by @\(kicker?.username ?? "???")")
            }
        case "leave":
            guard let channelId = data["channel_id"] as? String, let channel = self.channels[channelId] else {
                NSLog("%@", "WARNING: Got leave for unknown channel: \(data)")
                break
            }
            guard senderId != session.id else {
                self.channels.removeValue(forKey: channelId)
                self.leftChannel.emit(channelId)
                print("--- Current user left #\(channel.id)")
                break
            }
            if let account = channel.accounts.removeValue(forKey: senderId) {
                self.participantsChanged.emit(channel)
                print("--- @\(account.username) left #\(channel.id)")
            }
        case "text":
            guard
                let channelId = data["to"] as? String,
                let channel = self.channels[channelId],
                let account = channel.accounts[senderId]
                else
            {
                NSLog("%@", "WARNING: Got text for unknown channel/account: \(data)")
                break
            }
            guard let message = try? Message(channelId: channelId, senderId: senderId, data: data) else {
                NSLog("%@", "WARNING: Failed to turn data into message: \(data)")
                break
            }
            let entry = Channel.Entry(account: account, message: message)
            channel.history.append(entry)
            self.newMessage.emit(channel, entry)
            print("--- @\(account.username) in #\(channel.id): \(message.text)")
        default:
            NSLog("%@", "WARNING: Unhandled message type: \(type) \(data)")
        }
    }

    // MARK: - Private

    private let queue = DispatchQueue(label: "cam.reaction.ReactionCam.MessageService.Chat." + UUID().uuidString)
    private let socket: WebSocket

    private var autoReconnect = false
    private var backoff = BACKOFF_MIN
    private var pendingMessages = [Data]()
    private var session: Session?

    private init() {
        var request = URLRequest(url: ChatService.url)
        request.setValue("https://chat.reaction.cam", forHTTPHeaderField: "Origin")
        request.setValue(RequestInfo.userAgent, forHTTPHeaderField: "User-Agent")
        self.socket = WebSocket(request: request)
        self.socket.callbackQueue = self.queue
        self.socket.delegate = self
    }

    private func encode(command: String, _ arguments: [String: Any]) throws -> Data {
        guard var data = command.data(using: .utf8) else {
            throw MessageServiceError.invalidChatCommand
        }
        data.append(0x20) // Space.
        let json = try JSONSerialization.data(withJSONObject: arguments, options: [])
        data.append(json)
        return data
    }

    private func safelyWrite(command: String, _ arguments: DataType) {
        self.queue.async {
            guard let data = try? self.encode(command: command, arguments) else {
                return
            }
            guard self.socket.isConnected else {
                self.pendingMessages.append(data)
                if self.autoReconnect {
                    self.socket.connect()
                }
                return
            }
            self.socket.write(data: data)
        }
    }

    // MARK: - Channel

    class Channel {
        struct Entry {
            let account: MessageAccount
            let message: Message
        }

        let id: String

        fileprivate(set) var accounts = [Int64: MessageAccount]()
        fileprivate(set) var history = [Entry]()

        // MARK: - File Private

        fileprivate init(id: String, accounts: [MessageAccount], history: [Entry] = []) {
            self.id = id
            self.accounts = Dictionary(uniqueKeysWithValues: accounts.map({ ($0.id, $0) }))
            self.history = history
        }
    }
}
