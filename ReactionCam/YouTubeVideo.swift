import Foundation

struct YouTubeVideo {
    enum Status: String {
        case `private`, `public`, unlisted
    }

    let id: String
    let status: Status
    let thumbURL: URL?
    let title: String

    init?(data: DataType) {
        guard
            let id = data["id"] as? String,
            let status = (data["status"] as? String).flatMap(Status.init(rawValue:)),
            let title = data["title"] as? String
            else { return nil }
        self.id = id
        self.status = status
        self.thumbURL = (data["thumb_url"] as? String).flatMap(URL.init(string:))
        self.title = title
    }
}
