import Foundation

class AccountBase: Account {
    static func anonymousUser() -> Account {
        return AccountBase(id: 5091062658891776, username: "anonymous")
    }

    let id: Int64

    var contentCount: Int {
        return self.data["content_count"] as! Int
    }

    var displayName: String {
        return self.data["display_name"] as! String
    }

    var followerCount: Int {
        return self.data["follower_count"] as! Int
    }

    var followingCount: Int {
        return self.data["following_count"] as! Int
    }
    
    var hasRewards: Bool {
        return self.data["has_rewards"] as? Bool ?? false
    }

    var imageURL: URL? {
        if let url = self.data["image_url"] as? String {
            return URL(string: url)
        }
        return nil
    }

    var isBlocked: Bool {
        return self.data["is_blocked"] as? Bool ?? false
    }

    var isVerified: Bool {
        return self.data["verified"] as? Bool ?? false
    }

    var status: String {
        return self.data["status"] as! String
    }

    var username: String {
        return self.data["username"] as! String
    }

    init(data: DataType) {
        self.data = data
        self.id = (data["id"] as! NSNumber).int64Value
    }

    // MARK: Private

    private let data: DataType

    private init(id: Int64, username: String) {
        self.data = [
            "display_name": username,
            "properties": DataType(),
            "status": "unknown",
            "username": username,
        ]
        self.id = id
    }
}

extension AccountBase: Equatable {
    static func ==(lhs: AccountBase, rhs: AccountBase) -> Bool {
        return lhs.id == rhs.id
    }
}
