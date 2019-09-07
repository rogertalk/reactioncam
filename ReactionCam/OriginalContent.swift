import Foundation

class OriginalContent: ContentInfo {
    let creator: Account?
    let related: [ContentInfo]
    let poster: Account?

    override init?(data: DataType) {
        guard let contentData = data["content"] as? DataType else {
            return nil
        }
        self.creator = (data["creator"] as? DataType).flatMap(AccountBase.init(data:))
        self.poster = (data["poster"] as? DataType).flatMap(AccountBase.init(data:))
        self.related = (data["related"] as? [DataType])?.compactMap(ContentInfo.init) ?? [ContentInfo]()
        super.init(data: contentData)
    }
}
