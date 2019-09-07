import Foundation

class FollowService {
    static let instance = FollowService()

    func follow(ids: [Int64], callback: ((Bool) -> ())? = nil) {
        let stringIds = ids.map(String.init)
        Logging.info("Follow", ["Count": ids.count, "Ids": stringIds.joined(separator: ",")])
        Intent.follow(identifiers: stringIds).perform(BackendClient.api) {
            guard $0.successful else {
                callback?(false)
                return
            }
            self.followingIds.formUnion(ids)
            if let session = BackendClient.api.session {
                var data = session.account
                data["following_count"] = session.followingCount + 1
                BackendClient.api.session = session.withNewAccountData(data) ?? session
            }
            callback?(true)
        }
    }

    func isFollowing(_ id: Int64) -> Bool {
        return self.followingIds.contains(id)
    }

    func isFollowing(_ account: Account) -> Bool {
        return self.followingIds.contains(account.id)
    }

    func loadFollowing() {
        guard BackendClient.api.session != nil else {
            assertionFailure("Don't call loadFollowing() without a session")
            return
        }
        Intent.getOwnFollowing(limit: 1000, cursor: nil, idsOnly: true).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data, let list = data["data"] as? [Int64] else {
                return
            }
            self.followingIds = Set(list)
        }
    }

    func unfollow(id: Int64, callback: ((Bool) -> ())? = nil) {
        Logging.info("Unfollow", ["Id": String(id)])
        Intent.unfollow(identifier: String(id)).perform(BackendClient.api) {
            guard $0.successful else {
                callback?(false)
                return
            }
            self.followingIds.remove(id)
            if let session = BackendClient.api.session {
                var data = session.account
                data["following_count"] = session.followingCount - 1
                BackendClient.api.session = session.withNewAccountData(data) ?? session
            }
            callback?(true)
        }
    }

    // MARK: - Private

    private var followingIds = Set<Int64>()

    private init() { }
}
