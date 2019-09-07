import Foundation

// TODO: Make this the universal Account protocol.
struct MessageAccount {
    let id: Int64
    let imageURL: URL
    let isVerified: Bool
    let username: String

    var isCurrentUser: Bool {
        return self.id == BackendClient.api.session?.id
    }

    init(from account: Account) {
        self.id = account.id
        self.imageURL = account.imageURL!
        self.isVerified = account.isVerified
        self.username = account.username
    }

    init?(data: DataType) {
        guard
            let id = data["id"] as? Int64,
            let imageURL = (data["image_url"] as? String).flatMap(URL.init(string:)),
            let isVerified = data["verified"] as? Bool,
            let username = data["username"] as? String
            else { return nil }
        self.id = id
        self.imageURL = imageURL
        self.isVerified = isVerified
        self.username = username
    }
}
