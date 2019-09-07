import Foundation

class Content: ContentInfo {
    let creator: Account
    var relatedTo: ContentInfo?

    var creatorLabel: String {
        if let label = self.properties["creator_label"] as? String {
            return label
        }
        // TODO: Make this work.
        return (self.creator as? AccountWithExtras)?.label ?? "@\(self.creator.username)"
    }

    var isOriginal: Bool {
        return !self.tags.contains("reaction") && (self.tags.contains("original") && self.relatedTo == nil)
    }

    var titleLabel: String? {
        return (self.properties["title_short"] as? String)
            ?? self.title
            ?? self.relatedTo?.title.flatMap({ "\($0) REACTION" })
    }

    var voted: Bool {
        get {
            return self.containerData["voted"] as? Bool ?? false
        }
    }

    override init?(data: DataType) {
        self.containerData = data
        if let data = data["creator"] as? DataType {
            self.creator = AccountBase(data: data)
        } else {
            self.creator = AccountBase.anonymousUser()
        }
        self.relatedTo = (data["related_to"] as? DataType).flatMap(ContentInfo.init)
        super.init(data: data["content"] as! DataType)
    }

    func vote() {
        Intent.voteForContent(contentId: self.id).perform(BackendClient.api)
        self.containerData["voted"] = true
    }

    // MARK: - Private

    private var containerData: DataType
}
