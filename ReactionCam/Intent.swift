import CoreGraphics
import CoreLocation

/// The representation of an intent to request something of the API.
enum Intent {
    /// Requests a batch of tokens that can be used for uploading files.
    case allocateUploadTokens(contentType: String)
    /// Associates the current user's Facebook account with their reaction.cam account.
    case authFacebook(accessToken: String)
    /// Associates the current user's YouTube account with their reaction.cam account.
    case authYouTube(code: String)
    /// Blocks a user with the specified identifier.
    case blockUser(identifier: String)
    /// Changes the account password.
    case changePassword(newPassword: String, oldPassword: String?)
    /// Change location sharing privacy setting.
    case changeShareLocation(share: Bool)
    /// Comments on a piece of content.
    case commentContentThread(id: Int64, text: String, replyTo: String?)
    /// Comments on a piece of content.
    case commentContentTimeline(id: Int64, offset: Int, text: String)
    /// Creates a piece of content.
    case createContent(url: URL, duration: Int, tags: [String], title: String?,
        thumbnail: Image?, dimensions: CGSize?, relatedContent: ContentRef?,
        dedupe: String?, uploadToYouTube: Bool)
    /// Requests another user to create content based on the provided content.
    case createContentRequest(identifier: String, relatedContent: ContentRef)
    /// Gets or creates the original content for the provided metadata.
    case createOriginalContent(metadata: ContentRef)
    /// Requests the current user to create content based on the provided content, after a delay.
    case createOwnContentRequest(relatedContent: ContentRef, delay: TimeInterval)
    /// Puts up a public request to create content based on the provided content.
    case createPublicContentRequest(relatedContent: ContentRef, tags: [String])
    /// Deletes a comment (only possible if user created the content or the comment).
    case deleteContentComment(contentId: Int64, commentId: String)
    /// Flag content as offensive or otherwise breaking the rules.
    case flagContent(id: Int64)
    /// Follows one or more account(s).
    case follow(identifiers: [String])
    /// Requests an access code for logging into a service.
    case getAccessCode()
    /// Sends the user's contacts list and gets back active users.
    case getActiveContacts(identifiers: [String])
    /// Gets a specific piece of content.
    case getContent(id: Int64)
    /// Gets the comments for a specific piece of content.
    case getContentComments(id: Int64, sort: String?)
    /// Gets a specific piece of content by its slug.
    case getContentBySlug(slug: String)
    /// Gets a list of content for a specific tag.
    case getContentList(tags: [String], sortBy: String?, limit: Int?, cursor: String?)
    /// Gets a list of followers.
    case getFollowers(identifier: String, limit: Int?, cursor: String?)
    /// Gets a list of accounts being followed.
    case getFollowing(identifier: String, limit: Int?, cursor: String?)
    /// Gets a list of recent notifications.
    case getNotifications()
    /// Get a thread between the current user and the specified account.
    case getOrCreateThread(identifier: String)
    /// Gets a list of original content with additional metadata.
    case getOriginalContentList(sortBy: String?, limit: Int?, cursor: String?)
    /// Gets a list of content by the current user, for a specific tag.
    case getOwnContentList(tag: String, limit: Int?, cursor: String?)
    /// Gets a list of followers of the current user.
    case getOwnFollowers(limit: Int?, cursor: String?, idsOnly: Bool)
    /// Gets a list of accounts being followed by the current user.
    case getOwnFollowing(limit: Int?, cursor: String?, idsOnly: Bool)
    /// Gets the list of content from accounts being followed by the current user.
    case getOwnFollowingContentList(tag: String, cursor: String?)
    /// Gets the current user's profile.
    case getOwnProfile()
    /// Gets a feed of recent payments between users.
    case getPaymentsFeed()
    /// Gets the profile of a user with the specified identifier.
    case getProfile(identifier: String)
    /// Gets a list of comments by a specific user.
    case getProfileCommentList(identifier: String, cursor: String?)
    /// Gets a list of content for a specific tag by a specific user.
    case getProfileContentList(identifier: String, tag: String, limit: Int?, cursor: String?)
    /// Gets a list of originals by a specific user along with related content.
    case getProfileOriginalList(identifier: String, limit: Int?, cursor: String?)
    /// Gets the list of users that paid the most to the specified user.
    case getProfileTopPayers(identifier: String)
    /// Gets information about a specific public content request.
    case getPublicContentRequest(id: Int64)
    /// Gets a list of public content requests.
    case getPublicContentRequestList(tags: [String], sortBy: String?, limit: Int?, cursor: String?)
    /// Gets other content based on the specified content.
    case getRelatedContentList(contentId: Int64, tag: String, sortBy: String?, limit: Int?, cursor: String?)
    /// Gets a list of suggested accounts.
    case getSuggestedAccounts(limit: Int?)
    /// Gets a list of featured tags to display in the client.
    case getTags()
    /// Gets a list of messages in the specified thread.
    case getThreadMessages(threadId: String, cursor: String?)
    /// Gets a list of threads visible by the current user.
    case getThreads(cursor: String?)
    /// Gets the top ranked users by first posting of content.
    case getTopAccountsByFirst()
    /// Gets the top ranked users by received payments.
    case getTopAccountsByPaymentsReceived()
    /// Gets the top ranked users by votes.
    case getTopAccountsByVotes(tag: String?)
    /// Gets the top creators.
    case getTopCreators()
    /// Gets the top rewards.
    case getTopRewards()
    /// Gets a list of the user's YouTube videos (both public and private ones).
    case getYouTubeVideos(limit: Int?)
    /// Logs the user in with a username and password.
    case logIn(username: String, password: String)
    /// Logs the user in with an authorization code.
    case logInWithAuthCode(code: String)
    /// Logs the user out.
    case logOut()
    /// Marks a notification as having been seen.
    case markNotificationSeen(id: Int64)
    /// Sends a message to the specified thread.
    case messageThread(threadId: String, type: String, text: String, data: DataType?)
    /// Pays another user the specified amount.
    case pay(identifier: String, amount: Int, comment: String?)
    /// Pins content to the top of the user's profile.
    case pin(content: Content?)
    /// Gets a new access token using a refresh token.
    case refreshSession(refreshToken: String)
    /// Registers an account.
    case register(username: String?, password: String?, birthday: Date?, gender: Gender?)
    /// Registers the device for push notifications.
    case registerDeviceForPush(deviceId: String?, environment: String?, platform: String, token: String)
    /// Exchanges a receipt for currency.
    case registerPurchase(receipt: Data, purchases: [String])
    /// Reports a client event.
    case report(timestamp: Date, eventName: String, class: String, properties: [String: Any]?)
    /// Reports a batch of client events in one go.
    case reportBatch(events: Data)
    /// Requests a secret to the specified identifier (usually a phone number).
    case requestChallenge(identifier: String, preferPhoneCall: Bool)
    /// Resets (removes) the entry to a public content request.
    case resetPublicContentRequestEntry(requestId: Int64)
    /// Responds with a secret that was previously requested to prove ownership.
    case respondToChallenge(identifier: String, secret: String)
    /// Searches for accounts.
    case searchAccounts(query: String)
    /// Searches for content.
    case searchContent(query: String)
    /// Sends feedback from the user to us.
    case sendFeedback(message: String, email: String?)
    /// Request an invite to be sent to this number.
    case sendInvite(identifiers: [String], inviteToken: String?, names: [String]?)
    /// Request a service invite to be sent to these identifiers.
    case sendServiceInvite(service: String, teamId: String?, identifiers: [String])
    /// Sets the coordinates for the current user.
    case setLocation(location: CLLocation)
    /// Submits an entry to a public content request.
    case submitPublicContentRequestEntry(requestId: Int64, contentId: Int64?)
    /// Submits a YouTube video as an entry to a public content request.
    case submitPublicContentRequestEntryFromYouTube(requestId: Int64, videoId: String)
    /// Unblocks the user with the specified identifier.
    case unblockUser(identifier: String)
    /// Unfollows an account.
    case unfollow(identifier: String)
    /// Unlocks a premium property by paying for it.
    case unlockPremiumProperty(property: String)
    /// Stop sending push notifications to the provided token.
    case unregisterDeviceForPush(token: String)
    /// Updates a piece of content.
    case updateContent(contentId: Int64, tags: [String], title: String?, thumbnail: Image?)
    /// Updates the thumbnail for the specified content.
    case updateContentThumbnail(contentId: Int64, thumbnail: Image)
    /// Batch set multiple account properties.
    case updateProfile(username: String, image: Intent.Image?, properties: [String: Any])
    /// Changes the registered demographics of the current user (not public).
    case updateProfileDemographics(birthday: Date, gender: Gender)
    /// Changes the display name of the current user.
    case updateProfileDisplayName(newDisplayName: String)
    /// Changes the profile image of the current user.
    case updateProfileImage(image: Image)
    /// Sets public properties that will be exposed on the account profile.
    case updateProfileProperties(properties: [String: Any])
    /// Changes the username of the current user.
    case updateProfileUsername(username: String)
    /// Tells the backend to upload content to YouTube.
    case uploadToYouTube(contentId: Int64)
    /// Marks seen status for a message thread
    case updateThreadSeenUntil(threadId: String, messageId: String)
    /// Makes a thread visible/invisible.
    case updateThreadVisibility(threadId: String, visible: Bool)
    /// Marks a piece of content as viewed.
    case viewContent(contentId: Int64)
    /// Votes for a piece of content.
    case voteForContent(contentId: Int64)

    var retryable: Bool {
        switch self {
        case .createContent, .registerDeviceForPush, .report, .updateContent, .viewContent, .voteForContent:
            return true
        default:
            return false
        }
    }

    enum Gender: String {
        case female, male, other
    }

    enum Image {
        case jpeg(Data)
        case png(Data)
    }
}
