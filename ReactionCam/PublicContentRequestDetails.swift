import Foundation

struct PublicContentRequestDetails {
    struct Entry {
        let created: Date
        let rewardEarned: Int
        let youTubeURL: URL?
        let youTubeViews: Int

        init?(data: DataType) {
            guard
                let createdMS = data["created"] as? Double,
                let rewardEarned = data["reward_earned"] as? Int,
                let youTubeViews = data["youtube_views"] as? Int
                else { return nil }
            self.created = Date(timeIntervalSince1970: createdMS / 1000)
            self.rewardEarned = rewardEarned
            self.youTubeURL = (data["youtube_url"] as? String).flatMap(URL.init(string:))
            self.youTubeViews = youTubeViews
        }
    }

    enum Status: String {
        /// Data is still loading from the backend.
        case loading
        /// No entry has been submitted yet.
        case open
        /// The request has been closed from receiving further entries.
        case closed
        /// An entry has been created, waiting for content to upload.
        case pendingUpload = "pending-upload"
        /// Content has been uploaded, waiting for YouTube video to become visible.
        case pendingYouTube = "pending-youtube"
        /// YouTube video detected, waiting for approval by staff.
        case pendingReview = "pending-review"
        /// Entry has been approved and is earning rewards.
        case active
        /// Entry was denied in the review process.
        case denied
        /// Entry has become inactive for some reason.
        case inactive
    }

    let entry: Entry?
    let reaction: ContentInfo?
    let request: PublicContentRequest
    let status: Status
    let statusReason: String?

    init?(data: DataType) {
        guard
            let request = PublicContentRequest(data: data),
            let status = (data["status"] as? String).flatMap(Status.init(rawValue:))
            else { return nil }
        self.entry = (data["entry"] as? DataType).flatMap(Entry.init(data:))
        self.reaction = (data["reaction"] as? DataType).flatMap(ContentInfo.init(data:))
        self.request = request
        self.status = status
        self.statusReason = data["status_reason"] as? String
    }

    init(request: PublicContentRequest) {
        self.entry = nil
        self.reaction = nil
        self.request = request
        self.status = .loading
        self.statusReason = nil
    }
}
