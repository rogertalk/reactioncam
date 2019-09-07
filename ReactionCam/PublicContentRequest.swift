import Foundation

struct PublicContentRequest {
    let content: ContentInfo
    let id: Int64
    let isClosed: Bool
    let properties: DataType
    let reward: Int?

    var subtitle: String {
        return self.properties["subtitle"] as? String
            ?? self.content.properties["creator_label"] as? String
            ?? ""
    }

    var title: String {
        return self.properties["title"] as? String
            ?? self.content.properties["title_short"] as? String
            ?? self.content.title
            ?? ""
    }

    init?(data: DataType) {
        guard let requestData = data["request"] as? DataType, let id = requestData["id"] as? Int64 else {
            return nil
        }
        guard let content = (data["content"] as? DataType).flatMap(ContentInfo.init) else {
            return nil
        }
        self.content = content
        self.id = id
        self.isClosed = requestData["closed"] as? Bool ?? false
        self.properties = requestData["properties"] as? DataType ?? [:]
        self.reward = requestData["reward"] as? Int
    }
}
