import Foundation

struct ContentResult {
    let id: Int64
    let duration: TimeInterval
    let originalURL: URL?
    let relatedCount: Int
    let thumbnailURL: URL?
    let title: String?

    var ref: ContentRef {
        return .id(self.id)
    }

    init(data: DataType) {
        self.id = data["id"] as! Int64
        self.duration = TimeInterval(data["duration"] as! Int) / 1000
        self.originalURL = (data["original_url"] as? String).flatMap(URL.init(string:))
        self.relatedCount = data["related_count"] as! Int
        self.thumbnailURL = (data["thumb_url"] as? String).flatMap(URL.init(string:))
        self.title = data["title"] as? String
    }
}

extension ContentResult: Equatable {
    static func ==(lhs: ContentResult, rhs: ContentResult) -> Bool {
        return lhs.id == rhs.id
    }
}
