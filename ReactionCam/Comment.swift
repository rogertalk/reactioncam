import Foundation

struct Comment: Equatable {
    let creatorId: Int64
    let id: String
    let imageURL: URL?
    let offset: Int
    let replyTo: String?
    let text: String
    let username: String

    init(data: DataType) {
        self.creatorId = data["creator_id"] as! Int64
        self.id = data["id"] as! String
        self.imageURL = (data["creator_image_url"] as? String).flatMap(URL.init(string:))
        self.offset = data["offset"] as! Int
        self.replyTo = data["reply_to"] as? String
        self.text = data["text"] as! String
        self.username = data["creator_username"] as! String
    }

    init(comment: DataType, account: DataType) {
        self.creatorId = comment["creator_id"] as! Int64
        self.id = comment["id"] as! String
        self.imageURL = (account["image_url"] as? String).flatMap(URL.init(string:))
        self.offset = comment["offset"] as! Int
        self.replyTo = comment["reply_to"] as? String
        self.text = comment["text"] as! String
        self.username = account["username"] as! String
    }

    init(account: Account, offset: Int, text: String) {
        self.creatorId = account.id
        // Random temporary identifier to distinguish it in the UI
        self.id = "\(account.id)\(arc4random_uniform(1000))"
        self.imageURL = account.imageURL
        self.offset = offset
        self.replyTo = nil
        self.text = text
        self.username = account.username
    }

    init(account: Account, text: String, replyTo: String?) {
        self.creatorId = account.id
        // Random temporary identifier to distinguish it in the UI
        self.id = "\(account.id)\(arc4random_uniform(1000))"
        self.imageURL = account.imageURL
        self.offset = -1
        self.replyTo = replyTo
        self.text = text
        self.username = account.username
    }

    public static func ==(lhs: Comment, rhs: Comment) -> Bool {
        return lhs.id == rhs.id
    }
}
