import Foundation

class ContentInfo {
    let id: Int64
    let creatorId: Int64
    let created: Date
    var data: DataType
    let duration: TimeInterval
    let originalURL: URL?
    let properties: DataType
    let requestId: Int64?
    let tags: [String]
    let videoURL: URL?
    let webURL: URL?

    var commentCount: Int {
        return self.data["comment_count"] as! Int
    }

    var isFlagged: Bool {
        return SettingsManager.flaggedContentIds.contains(self.id)
    }

    var ref: ContentRef {
        return .id(self.id)
    }

    var relatedCount: Int {
        return self.data["related_count"] as! Int
    }

    var thumbnailURL: URL? {
        return (self.data["thumb_url"] as? String).flatMap(URL.init(string:))
    }
    
    var title: String? {
        return data["title"] as? String
    }

    var views: Int {
        return self.data["views"] as! Int
    }

    var votes: Int {
        return self.data["votes"] as! Int
    }

    init?(data: DataType) {
        self.data = data
        self.id = data["id"] as! Int64
        self.created = Date(timeIntervalSince1970: (data["created"] as! NSNumber).doubleValue / 1000)
        self.creatorId = data["creator_id"] as! Int64
        self.duration = TimeInterval(data["duration"] as! Int) / 1000
        self.originalURL = (data["original_url"] as? String).flatMap(URL.init(string:))
        self.properties = (data["properties"] as? DataType) ?? [:]
        self.requestId = data["request_id"] as? Int64
        self.tags = data["tags"] as! [String]
        self.videoURL = (data["video_url"] as? String).flatMap(URL.init(string:))
        self.webURL = (data["url"] as? String).flatMap(URL.init(string:))
        if self.isFlagged {
            return nil
        }
    }

    func flag() {
        SettingsManager.toggleFlaggedContent(id: self.id, value: true)
        Intent.flagContent(id: self.id).perform(BackendClient.api)
    }

    func update(with content: ContentInfo) {
        guard content.id == self.id else {
            return
        }
        self.data = content.data
    }
}


extension ContentInfo: Equatable {
    static func ==(lhs: ContentInfo, rhs: ContentInfo) -> Bool {
        return lhs.id == rhs.id
    }
}
