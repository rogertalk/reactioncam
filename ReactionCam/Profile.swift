import Foundation

class Profile: AccountBase, AccountWithExtras, AccountWithFollowState {
    var isFollowing: Bool {
        return self.data["is_following"] as! Bool
    }

    var properties: [String: Any] {
        return (self.data["properties"] as? DataType) ?? [:]
    }

    override init(data: DataType) {
        self.data = data
        super.init(data: data)
    }

    func toggleFollowing(callback: @escaping (Bool) -> ()) {
        if self.isFollowing {
            FollowService.instance.unfollow(id: self.id) {
                guard $0 else {
                    callback(false)
                    return
                }
                self.data["is_following"] = false
                callback(true)
            }
        } else {
            FollowService.instance.follow(ids: [self.id]) {
                guard $0 else {
                    callback(false)
                    return
                }
                self.data["is_following"] = true
                callback(true)
            }
        }
    }

    // MARK: Private

    private var data: DataType
}
