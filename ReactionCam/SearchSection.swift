import UIKit

protocol SearchSectionDelegate: class {
    func searchSection(_ section: TableViewSection, didSelectAccount account: Account)
    func searchSection(_ section: TableViewSection, didSelectContentResult content: ContentResult)
    func searchSectionNeedsReload(_ section: TableViewSection)
    func searchSection(_ section: TableViewSection, shouldShowAccount account: Account) -> Bool
}

class SearchUserSection: TableViewSection {
    private(set) var isPerformingSearch: Bool = false

    var cellReuseIdentifier: String {
        return "UserCell"
    }

    var count: Int {
        return self.isPerformingSearch ? 1 : self.results.count
    }

    var headerTitle: String? {
        return "More..."
    }

    var resultsCount: Int {
        return self.isPerformingSearch ? 0 : self.results.count
    }

    var rowHeight: CGFloat {
        return 65
    }

    var subscriptions = [Account]() {
        didSet {
            self.filterResults()
        }
    }

    init(delegate: SearchSectionDelegate) {
        self.delegate = delegate
    }

    func handleSelect(_ row: Int) -> SectionAction {
        guard row < self.results.count else {
            return BasicAction.nothing
        }
        let account = self.results[row]
        let isFollowing = self.subscriptions.contains(where: { $0.id == account.id })
        let type: String
        if self.backendResults.contains(where: { $0.id == account.id }) {
            type = "Username"
        } else if SettingsManager.recentAccounts.contains(where: { $0.id == account.id}) {
            type = "RecentChoice"
        } else if isFollowing {
            type = "Follow"
        } else {
            type = "Unknown"
        }
        Logging.log("Search User Selected", [
            "Username": account.username,
            "Type": type,
            "IsFollowing": isFollowing])
        // Track selection for easier access next time.
        SettingsManager.trackRecentAccount(account)
        self.delegate?.searchSection(self, didSelectAccount: account)
        return BasicAction.nothing
    }

    func populateCell(_ row: Int, cell: UITableViewCell) {
        let cell = cell as! UserCell
        guard !self.isPerformingSearch else {
            cell.user = nil
            cell.titleLabel.text = "Searching for \"\(self.currentQuery ?? "user")\""
            cell.followButton.isLoading = true
            cell.followButton.isUserInteractionEnabled = false
            cell.followButton.isHidden = false
            return
        }
        cell.followButton.isHidden = true
        cell.user = self.results[row]
    }

    func search(_ text: String) {
        let query = text.lowercased()
        self.currentQuery = query
        let isValidSearch = !query.isEmpty

        self.backendResults = []
        // Set this to show "Searching..."
        self.isPerformingSearch = isValidSearch
        self.filterResults()

        guard isValidSearch else {
            return
        }
        self.searchTimer?.invalidate()
        self.searchTimer =
            Timer.scheduledTimer(timeInterval: 0.3,
                                 target: self,
                                 selector: #selector(SearchUserSection.performSearch),
                                 userInfo: query,
                                 repeats: false)

    }

    private func filterResults() {
        var seen = Set<Int64>()
        var results = [Account]()
        // Utility functions for ensuring accounts only get added once.
        func add(_ account: Account) {
            if let delegate = self.delegate, !delegate.searchSection(self, shouldShowAccount: account) {
                return
            }
            guard !seen.contains(account.id) else { return }
            results.append(account)
            seen.insert(account.id)
        }
        func addAll<T: Sequence>(_ accounts: T) where T.Iterator.Element == Account {
            accounts.forEach(add)
        }
        // Always show the first result from the backend at the top.
        if let account = self.backendResults.first {
            add(account)
        }
        // Perform the search on local data.
        if let query = self.currentQuery, !query.isEmpty {
            let filter: ([Account]) -> [Account] = { $0.filter { $0.username.contains(query) } }
            addAll(filter(SettingsManager.recentAccounts))
            addAll(filter(self.subscriptions))
        } else {
            addAll(SettingsManager.recentAccounts)
            addAll(self.subscriptions)
        }
        // Insert remaining backend results at the end.
        addAll(self.backendResults.dropFirst())
        self.results = results
        self.delegate?.searchSectionNeedsReload(self)
    }

    @objc dynamic private func performSearch(timer: Timer) {
        guard let query = timer.userInfo as? String else {
            return
        }
        Intent.searchAccounts(query: query).perform(BackendClient.api) {
            // Ensure we are still searching for the same query.
            guard query == self.currentQuery else {
                return
            }
            self.isPerformingSearch = false
            if $0.successful, let data = $0.data?["data"] as? [DataType] {
                self.backendResults = data.compactMap { AccountBase(data: $0) }
            } else {
                self.backendResults = []
            }
            self.filterResults()
        }
    }

    // MARK: - Private

    private weak var delegate: SearchSectionDelegate?

    private var backendResults = [Account]()
    private var currentQuery: String? = nil
    private var results = [Account]()
    private var searchTimer: Timer?
}

class SearchTopicSection: TableViewSection {
    private(set) var isPerformingSearch: Bool = false

    var cellReuseIdentifier: String {
        return "SearchResultCell"
    }

    var count: Int {
        return self.isPerformingSearch ? 0 : self.cachedResults.count
    }

    var headerTitle: String? {
        return nil
    }

    var results: [ContentResult] {
        return self.isPerformingSearch ? [] : self.cachedResults
    }

    var rowHeight: CGFloat {
        return 80
    }

    init(delegate: SearchSectionDelegate) {
        self.delegate = delegate
    }

    func handleSelect(_ row: Int) -> SectionAction {
        guard row < self.cachedResults.count else {
            return BasicAction.nothing
        }
        self.delegate?.searchSection(self, didSelectContentResult: self.cachedResults[row])
        return BasicAction.nothing
    }

    func populateCell(_ row: Int, cell: UITableViewCell) {
        let cell = cell as! SearchResultCell
        let content = self.cachedResults[row]
        cell.contentSuggestionView.titleLabel.text = content.title
        if content.relatedCount > 0 {
            cell.contentSuggestionView.reactionsLabel.text = "\(content.relatedCount.countLabelShort) reactions"
            cell.contentSuggestionView.reactionsLabel.isHidden = false
        } else {
            cell.contentSuggestionView.reactionsLabel.isHidden = true
        }
        if let url = content.thumbnailURL {
            cell.contentSuggestionView.thumbnailButton.af_setImageBiased(for: .normal, url: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
        } else {
            cell.contentSuggestionView.thumbnailButton.setImage(#imageLiteral(resourceName: "relatedContent"), for: .normal)
        }
    }

    func search(_ text: String) {
        let query = text.lowercased()
        self.currentQuery = query
        let isValidSearch = !query.isEmpty

        // Set this to show "Searching..."
        self.isPerformingSearch = isValidSearch

        guard isValidSearch else {
            self.cachedResults = []
            self.delegate?.searchSectionNeedsReload(self)
            return
        }
        self.searchTimer?.invalidate()
        self.searchTimer =
            Timer.scheduledTimer(timeInterval: 0.3,
                                 target: self,
                                 selector: #selector(SearchTopicSection.performSearch),
                                 userInfo: query,
                                 repeats: false)

    }

    @objc dynamic private func performSearch(timer: Timer) {
        guard let query = timer.userInfo as? String else {
            return
        }
        ContentService.instance.search(query: query) {
            // Ensure we are still searching for the same query.
            guard query == self.currentQuery else {
                return
            }
            self.isPerformingSearch = false
            self.cachedResults = $0
            self.delegate?.searchSectionNeedsReload(self)
        }
    }

    // MARK: - Private

    private var cachedResults = [ContentResult]()
    private var currentQuery: String? = nil
    private weak var delegate: SearchSectionDelegate?
    private var searchTimer: Timer?
}
