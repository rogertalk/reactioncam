import Foundation

protocol Account {
    var id: Int64 { get }
    var contentCount: Int { get }
    var displayName: String { get }
    var followerCount: Int { get }
    var followingCount: Int { get }
    var hasRewards: Bool { get }
    var imageURL: URL? { get }
    var isBlocked: Bool { get }
    var isVerified: Bool { get }
    var username: String { get }
    var status: String { get }
}

protocol AccountWithExtras: Account {
    var properties: DataType { get }
}

protocol AccountWithFollowState: Account {
    var isFollowing: Bool { get }

    func toggleFollowing(callback: @escaping (Bool) -> ())
}

extension Account {
    var isActive: Bool {
        return self.status == "active"
    }

    var isAnonymousUser: Bool {
        return self.id == 5091062658891776
    }

    var isCurrentUser: Bool {
        guard let currentUserId = BackendClient.api.session?.id else {
            return false
        }
        return self.id == currentUserId
    }
}

struct PinnedContent {
    struct Related {
        let id: Int64
        let thumbnailURL: URL?
        let title: String?
        let webURL: URL?

        var data: DataType {
            return [
                "id": self.id,
                "thumb_url": self.thumbnailURL?.absoluteString ?? NSNull(),
                "title": self.title ?? NSNull(),
                "url": self.webURL?.absoluteString ?? NSNull(),
            ]
        }

        init(content: ContentInfo) {
            self.id = content.id
            self.thumbnailURL = content.thumbnailURL
            self.title = content.title
            self.webURL = content.webURL
        }

        init?(data: DataType) {
            guard let id = data["id"] as? Int64 else {
                return nil
            }
            self.id = id
            self.thumbnailURL = (data["thumb_url"] as? String).flatMap(URL.init(string:))
            self.title = data["title"] as? String
            self.webURL = (data["url"] as? String).flatMap(URL.init(string:))
        }
    }

    let created: Date
    let duration: TimeInterval
    let id: Int64
    let pinned: Date
    let relatedTo: Related?
    let tags: [String]
    let thumbnailURL: URL?
    let title: String?
    let webURL: URL?

    var data: DataType {
        return [
            "created": Int64(self.created.timeIntervalSince1970 * 1000),
            "duration": Int(self.duration * 1000),
            "id": self.id,
            "pinned": Int64(Date().timeIntervalSince1970 * 1000),
            "related_to": self.relatedTo?.data ?? NSNull(),
            "tags": self.tags,
            "thumb_url": self.thumbnailURL?.absoluteString ?? NSNull(),
            "title": self.title ?? NSNull(),
            "url": self.webURL?.absoluteString ?? NSNull(),
        ]
    }

    init(content: Content) {
        self.created = content.created
        self.duration = content.duration
        self.id = content.id
        self.pinned = Date()
        self.relatedTo = content.relatedTo.flatMap { Related(content: $0) }
        self.tags = content.tags
        self.thumbnailURL = content.thumbnailURL
        self.title = content.title
        self.webURL = content.webURL
    }

    init?(data: DataType) {
        guard
            let created = (data["created"] as? Int64).flatMap({ Date(timeIntervalSince1970: Double($0) / 1000) }),
            let duration = (data["duration"] as? Int).flatMap({ TimeInterval($0) / 1000 }),
            let id = data["id"] as? Int64,
            let pinned = (data["pinned"] as? Int64).flatMap({ Date(timeIntervalSince1970: Double($0) / 1000) }),
            let tags = data["tags"] as? [String]
            else { return nil }
        self.id = id
        self.created = created
        self.duration = duration
        self.pinned = pinned
        self.relatedTo = (data["related_to"] as? DataType).flatMap(Related.init(data:))
        self.tags = tags
        self.thumbnailURL = (data["thumb_url"] as? String).flatMap(URL.init(string:))
        self.title = data["title"] as? String
        self.webURL = (data["url"] as? String).flatMap(URL.init(string:))
    }
}

extension AccountWithExtras {
    var hasChatEnabled: Bool {
        return self.properties["chat_enabled"] as? Bool ?? false
    }

    var label: String {
        if (self.status == "unclaimed" || self.isVerified) && self.displayName != self.username {
            return self.displayName
        }
        return "@\(self.username)"
    }

    var pinnedContent: PinnedContent? {
        guard let data = self.properties["pinned_content"] as? DataType else {
            return nil
        }
        return PinnedContent(data: data)
    }
}
