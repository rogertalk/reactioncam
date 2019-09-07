import Foundation

enum ContentRef {
    case id(Int64)
    case metadata(creator: String, url: URL, duration: Int, title: String, videoURL: URL?, thumbURL: URL?)
    case url(URL)
}

extension ContentRef {
    static func fromDict(_ dict: [String: Any]) -> ContentRef? {
        guard let type = dict["type"] as? String else {
            return nil
        }
        switch type {
        case "id":
            guard let id = (dict["id"] as? NSNumber)?.int64Value else {
                return nil
            }
            return .id(id)
        case "metadata":
            guard
                let creator = dict["creator"] as? String,
                let url = (dict["url"] as? String).flatMap(URL.init(string:)),
                let duration = (dict["duration"] as? NSNumber)?.intValue,
                let title = dict["title"] as? String
                else { return nil }
            return .metadata(creator: creator, url: url, duration: duration, title: title,
                             videoURL: (dict["video_url"] as? String).flatMap(URL.init(string:)),
                             thumbURL: (dict["thumb_url"] as? String).flatMap(URL.init(string:)))
        case "url":
            guard let url = (dict["url"] as? String).flatMap(URL.init(string:)) else {
                return nil
            }
            return .url(url)
        default:
            return nil
        }
    }

    func toDict() -> [String: Any] {
        switch self {
        case let .id(id):
            return [
                "type": "id",
                "id": NSNumber(value: id),
            ]
        case let .metadata(creator, url, duration, title, videoURL, thumbURL):
            return [
                "type": "metadata",
                "creator": creator,
                "url": url.absoluteString,
                "duration": NSNumber(value: duration),
                "title": title,
                "video_url": videoURL?.absoluteString ?? NSNull(),
                "thumb_url": thumbURL?.absoluteString ?? NSNull(),
            ]
        case let .url(url):
            return [
                "type": "url",
                "url": url.absoluteString,
            ]
        }
    }
}
