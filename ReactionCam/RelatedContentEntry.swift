import Foundation

class RelatedContentEntry: Equatable {
    static func ==(lhs: RelatedContentEntry, rhs: RelatedContentEntry) -> Bool {
        if let lhsId = lhs.id, let rhsId = rhs.id, lhsId == rhsId {
            return true
        }
        switch (lhs.ref, rhs.ref) {
        case let (.metadata(_, lhsUrl, _, _, _, _), .metadata(_, rhsUrl, _, _, _, _)):
            return lhsUrl == rhsUrl
        default:
            return false
        }
    }

    private(set) var content: ContentInfo?
    var id: Int64? {
        if case let .id(id) = self.ref {
            return id
        }
        return self.content?.id
    }
    var mappedRef: ContentRef {
        guard let content = self.content else {
            return self.ref
        }
        return content.ref
    }
    var ref: ContentRef {
        didSet {
            guard
                !self.isAutoFixing,
                let c = self.content,
                case let .metadata(_, _, duration, title, _, thumbURL) = self.ref,
                (c.duration == 0 && duration > 0) || (c.title == "YouTube" && title != c.title) || (c.thumbnailURL == nil && thumbURL != nil)
                else { return }
            // The original content could use an update.
            self.isAutoFixing = true
            self.lookUp(force: true) {
                self.isAutoFixing = false
            }
        }
    }
    var visibleInRecording = false

    init(content: ContentInfo) {
        self.content = content
        self.ref = content.ref
    }

    init(ref: ContentRef) {
        self.ref = ref
    }

    func lookUp(force: Bool = false, completion: @escaping () -> ()) {
        guard force || self.content == nil else {
            return
        }
        let callback = { (result: IntentResult) in
            guard result.successful, let data = result.data, let content = Content(data: data) else {
                return
            }
            self.content = content
            completion()
        }
        switch self.ref {
        case let .id(id):
            Intent.getContent(id: id).perform(BackendClient.api, callback: callback)
        case .metadata:
            Intent.createOriginalContent(metadata: self.ref).perform(BackendClient.api, callback: callback)
        default:
            break
        }
    }

    // MARK: - Private

    private var isAutoFixing = false
}
