import Foundation

// TODO: Inherit from a protocol that only requires id, username and image.
struct ThreadAccount {
    let id: Int64
    let imageURL: URL
    let isVerified: Bool
    let joined: Date
    let seenUntil: String?
    let seenUntilTimestamp: Date
    let username: String

    init(id: Int64) {
        self.id = id
        self.joined = Date()
        self.seenUntil = nil
        self.seenUntilTimestamp = Date()
        if let session = BackendClient.api.session, session.id == id {
            self.imageURL = session.imageURL!
            self.username = session.username
            self.isVerified = session.isVerified
        } else {
            self.imageURL = URL(string: "https://storage.googleapis.com/roger-api-persistent/82e06791b99eee1db92511c2cffffecb047d9d2016e0e70cdae6508f1beb3be7.png")!
            self.username = "user"
            self.isVerified = false
        }
    }

    init(data: DataType) {
        self.id = data["id"] as! Int64
        self.imageURL = URL(string: data["image_url"] as! String)!
        self.isVerified = (data["verified"] as? Bool) ?? false
        self.joined = Date(timeIntervalSince1970: (data["joined"] as! Double) / 1000)
        self.seenUntil = data["seen_until"] as? String
        self.seenUntilTimestamp = Date(timeIntervalSince1970: (data["seen_until_timestamp"] as! Double) / 1000)
        self.username = data["username"] as! String
    }
}
