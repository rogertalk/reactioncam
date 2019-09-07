import AlamofireImage
import UIKit

fileprivate let USER_SECTION_INVITE = 0
fileprivate let USER_SECTION_RESULT = 1

fileprivate let CONTENT_SECTION_SUGGESTIONS = 0
fileprivate let CONTENT_SECTION_GOOGLE = 1
fileprivate let CONTENT_SECTION_TAG = 2
fileprivate let CONTENT_SECTION_RESULT = 3

protocol SearchViewDelegate: class {
    func searchView(_ view: SearchView, didSelect result: SearchView.Result)
    func searchViewShouldShowAccounts(_ view: SearchView) -> Bool
    func searchViewShouldShowAccountsVip(_ view: SearchView) -> Bool
    func searchViewShouldShowTags(_ view: SearchView) -> Bool
}

class SearchView: UIView,
    UITableViewDelegate,
    UITableViewDataSource,
    UITextFieldDelegate,
    UIScrollViewDelegate,
    ConversationImportDelegate,
    SearchSectionDelegate {

    enum Result {
        case account(Account)
        case content(ContentResult, source: String)
        case googleQuery(String)
        case tag(String)
    }

    @IBOutlet weak var containerScrollView: UIScrollView!
    @IBOutlet weak var searchField: SearchTextField!
    @IBOutlet weak var searchSegmentedControl: UISegmentedControl!
    @IBOutlet weak var searchAccountsTable: UITableView!
    @IBOutlet weak var searchAccountsVipTable: UITableView!
    @IBOutlet weak var searchContentTable: UITableView!

    var contentResults: [ContentResult] {
        guard self.isSearching else {
            return self.contentSuggestions
        }
        return self.searchContentSection.results
    }

    var conversationImportAnchorView: UIView {
        return self
    }

    weak var delegate: SearchViewDelegate?
    var presenter: UIViewController!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.containerScrollView.delegate = self

        self.searchAccountsTable.delegate = self
        self.searchAccountsTable.dataSource = self
        self.searchAccountsTable.keyboardDismissMode = .onDrag
        self.searchAccountsTable.register(UINib(nibName: "UserCell", bundle: nil), forCellReuseIdentifier: "UserCell")
        self.searchAccountsTable.register(UINib(nibName: "InviteFriendCell", bundle: nil), forCellReuseIdentifier: "InviteFriendCell")

        self.searchAccountsVipTable.delegate = self
        self.searchAccountsVipTable.dataSource = self
        self.searchAccountsVipTable.keyboardDismissMode = .onDrag
        self.searchAccountsVipTable.register(UINib(nibName: "UserCell", bundle: nil), forCellReuseIdentifier: "UserCell")

        self.searchContentTable.delegate = self
        self.searchContentTable.dataSource = self
        self.searchContentTable.keyboardDismissMode = .onDrag
        self.searchContentTable.register(UINib(nibName: "SearchResultCell", bundle: nil), forCellReuseIdentifier: "SearchResultCell")
        self.searchContentTable.register(UINib(nibName: "UserCell", bundle: nil), forCellReuseIdentifier: "UserCell")

        self.searchAccountsSection = SearchUserSection(delegate: self)
        self.searchAccountsVipSection = SearchUserSection(delegate: self)
        self.searchContentSection = SearchTopicSection(delegate: self)

        self.searchField.delegate = self
        self.searchField.keyboardType = .twitter
        self.searchField.placeholder = "Search videos"

        ContentService.instance.search(query: "") {
            self.contentSuggestions = $0
            self.searchContentTable.reloadData()
        }
    }
    
    func refreshSubscriptions() {
        if let delegate = self.delegate, !delegate.searchViewShouldShowAccounts(self) && !delegate.searchViewShouldShowAccountsVip(self) {
            return
        }
        Intent.getOwnFollowing(limit: nil, cursor: nil, idsOnly: false).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [[String: Any]] else {
                return
            }
            let accounts = data.compactMap(AccountBase.init(data:))
            self.searchAccountsSection.subscriptions = accounts
            self.searchAccountsVipSection.subscriptions = accounts
        }
    }

    func show(searchString: String? = nil) {
        // TODO: Also support the inverse (no videos, only channels).
        if let delegate = self.delegate {
            self.searchSegmentedControl.isHidden = !delegate.searchViewShouldShowAccounts(self) && !delegate.searchViewShouldShowAccountsVip(self)
        } else {
            self.searchSegmentedControl.isHidden = true
        }
        if searchString != nil {
            self.searchField.text = searchString
            self.search()
        }
        self.showAnimated()
        self.searchField.becomeFirstResponder()
    }
    
    // MARK: - Actions

    @IBAction func searchFieldEditingChanged(_ sender: UITextField) {
        defer {
            self.searchAccountsTable.reloadData()
            self.searchAccountsVipTable.reloadData()
            self.searchContentTable.reloadData()
        }
        self.search()
    }

    @IBAction func cancelTapped(_ sender: Any) {
        self.hideAnimated()
        self.searchField.text = ""
        self.searchAccountsSection.search("")
        self.searchAccountsVipSection.search("")
        self.searchContentSection.search("")
        self.searchField.resignFirstResponder()
    }

    @IBAction func tabChanged(_ sender: UISegmentedControl) {
        self.endEditing(true)
        switch sender.selectedSegmentIndex {
        case 0:
            self.searchField.placeholder = "Search videos"
        case 1:
            if let delegate = self.delegate, delegate.searchViewShouldShowAccountsVip(self) {
                self.searchField.placeholder = "Search artists"
            } else {
                self.searchField.placeholder = "Search users"
            }
        case 2:
            self.searchField.placeholder = "Search users"
        default:
            self.searchField.placeholder = "?"
        }
        let offset = CGPoint(x: self.bounds.width * CGFloat(sender.selectedSegmentIndex), y: 0)
        self.containerScrollView.setContentOffset(offset, animated: true)
    }
    
    // MARK: - SearchSectionDelegate

    func searchSection(_ section: TableViewSection, didSelectAccount account: Account) {
        self.delegate?.searchView(self, didSelect: .account(account))
    }

    func searchSection(_ section: TableViewSection, didSelectContentResult content: ContentResult) {
        self.delegate?.searchView(self, didSelect: .content(content, source: "Search Result"))
    }

    func searchSectionNeedsReload(_ section: TableViewSection) {
        var titles = [String]()
        let contentCount = self.searchContentSection.count
        titles.append("VIDEOS\(contentCount > 0 ? " (\(contentCount))" : "")")
        if let delegate = self.delegate, delegate.searchViewShouldShowAccountsVip(self) {
            let accountsVipCount = self.searchAccountsVipSection.resultsCount
            titles.append("ARTISTS\(accountsVipCount > 0 ? " (\(accountsVipCount))" : "")")
            self.searchAccountsVipTable.isHidden = false
        } else {
            self.searchAccountsVipTable.isHidden = true
        }
        if let delegate = self.delegate, delegate.searchViewShouldShowAccounts(self) {
            let accountsCount = self.searchAccountsSection.resultsCount
            titles.append("USERS\(accountsCount > 0 ? " (\(accountsCount))" : "")")
            self.searchAccountsTable.isHidden = false
        } else {
            self.searchAccountsTable.isHidden = true
        }
        self.configureSegments(segments: titles)
        // TODO: Only reload relevant stuff.
        self.searchAccountsTable.reloadData()
        self.searchAccountsVipTable.reloadData()
        self.searchContentTable.reloadData()
    }

    func searchSection(_ section: TableViewSection, shouldShowAccount account: Account) -> Bool {
        guard let sus = section as? SearchUserSection else {
            return false
        }
        if sus === self.searchAccountsSection {
            let vipVisible = self.delegate?.searchViewShouldShowAccountsVip(self) ?? false
            return !account.isVerified || !vipVisible
        } else if sus === self.searchAccountsVipSection {
            return account.isVerified
        }
        return false
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard string != "\n" else {
            textField.resignFirstResponder()
            return false
        }
        return true
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let source: String
        var value: String? = nil
        switch tableView {
        case self.searchAccountsTable:
            switch indexPath.section {
            case USER_SECTION_INVITE:
                let alert = ConversationImportAlert(title: nil, message: nil, source: "Search", importActions: [.invite], owner: self.presenter, delegate: self)
                alert.show()
                self.importAlert = alert
                source = "Invite"
            case USER_SECTION_RESULT:
                let _ = self.searchAccountsSection.handleSelect(indexPath.row)
                source = "SearchResult"
            default:
                return
            }
        case self.searchAccountsVipTable:
            switch indexPath.section {
            case 0:
                let _ = self.searchAccountsVipSection.handleSelect(indexPath.row)
                source = "SearchResult"
            default:
                return
            }
        case self.searchContentTable:
            switch indexPath.section {
            case CONTENT_SECTION_SUGGESTIONS:
                let content = self.contentSuggestions[indexPath.row]
                self.delegate?.searchView(self, didSelect: .content(content, source: "Suggestion"))
                source = "Suggestion"
            case CONTENT_SECTION_GOOGLE:
                let search = self.searchField.text ?? ""
                self.delegate?.searchView(self, didSelect: .googleQuery(search))
                source = "Google"
                value = search
            case CONTENT_SECTION_TAG:
                guard let cell = tableView.cellForRow(at: indexPath) as? UserCell, var tag = cell.titleLabel.text else {
                    return
                }
                source = "TagResult"
                if tag.hasPrefix("#") {
                    tag.remove(at: tag.startIndex)
                }
                self.delegate?.searchView(self, didSelect: .tag(tag))
                value = tag
            case CONTENT_SECTION_RESULT:
                // Log search selection data
                let _ = self.searchContentSection.handleSelect(indexPath.row)
                source = "SearchTopicResult"
            default:
                return
            }
        default:
            return
        }
        var parameters = ["Source": source, "Index": String(indexPath.row)]
        if let value = value {
            parameters["Value"] = value
        }
        Logging.log("Search View Action", parameters)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return !self.isSearching && tableView == self.searchContentTable && section == CONTENT_SECTION_SUGGESTIONS ? 50 : 0.001
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !self.isSearching else {
            return nil
        }
        let header: String
        switch tableView {
        case self.searchContentTable:
            switch section {
            case CONTENT_SECTION_SUGGESTIONS:
                header = "Popular Searches"
            default:
                return nil
            }
        default:
            return nil
        }
        let headerView = UIView()
        headerView.frame = CGRect(x: 0, y: 0, width: tableView.frame.width, height: 50)
        headerView.backgroundColor = UIColor.uiBlack.withAlphaComponent(0.95)
        let textLabel = UILabel(frame: headerView.bounds.offsetBy(dx: 18, dy: 0))
        textLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        textLabel.textColor = .white
        textLabel.text = header
        headerView.addSubview(textLabel)
        return headerView
    }
    
    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch tableView {
        case self.searchAccountsTable:
            switch section {
            case USER_SECTION_INVITE:
                return 1
            case USER_SECTION_RESULT:
                return self.searchAccountsSection.resultsCount
            default:
                return 0
            }
        case self.searchAccountsVipTable:
            switch section {
            case 0:
                return self.searchAccountsVipSection.resultsCount
            default:
                return 0
            }
        case self.searchContentTable:
            switch section {
            case CONTENT_SECTION_SUGGESTIONS:
                return self.searchField.text?.isEmpty ?? true ? self.contentSuggestions.count : 0
            case CONTENT_SECTION_GOOGLE:
                guard
                    !self.searchContentSection.isPerformingSearch,
                    let text = self.searchField.text,
                    !text.isEmpty,
                    !text.contains("#"),
                    !text.contains("@")
                    else { return 0 }
                return 1
            case CONTENT_SECTION_TAG:
                guard
                    self.delegate?.searchViewShouldShowTags(self) ?? true,
                    !self.searchContentSection.isPerformingSearch,
                    let text = self.searchField.text,
                    !text.isEmpty,
                    !text.contains("@")
                    else { return 0 }
                return 1
            case CONTENT_SECTION_RESULT:
                return self.searchContentSection.count
            default:
                return 0
            }
        default:
            return 0
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        switch tableView {
        case self.searchAccountsTable:
            return 2
        case self.searchAccountsVipTable:
            return 1
        case self.searchContentTable:
            return 4
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch tableView {
        case self.searchAccountsTable:
            switch indexPath.section {
            case USER_SECTION_INVITE:
                return tableView.dequeueReusableCell(withIdentifier: "InviteFriendCell", for: indexPath)
            case USER_SECTION_RESULT:
                let cell = tableView.dequeueReusableCell(withIdentifier: self.searchAccountsSection.cellReuseIdentifier, for: indexPath)
                self.searchAccountsSection.populateCell(indexPath.row, cell: cell)
                return cell
            default:
                return UITableViewCell()
            }
        case self.searchAccountsVipTable:
            switch indexPath.section {
            case 0:
                let cell = tableView.dequeueReusableCell(withIdentifier: self.searchAccountsVipSection.cellReuseIdentifier, for: indexPath)
                self.searchAccountsVipSection.populateCell(indexPath.row, cell: cell)
                return cell
            default:
                return UITableViewCell()
            }
        case self.searchContentTable:
            switch indexPath.section {
            case CONTENT_SECTION_SUGGESTIONS:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath) as! SearchResultCell
                let content = self.contentSuggestions[indexPath.row]
                cell.contentSuggestionView.titleLabel.text = content.title
                cell.contentSuggestionView.reactionsLabel.isHidden = true
                if let url = content.thumbnailURL {
                    cell.contentSuggestionView.thumbnailButton.af_setImageBiased(for: .normal, url: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
                } else {
                    cell.contentSuggestionView.thumbnailButton.setImage(#imageLiteral(resourceName: "relatedContent"), for: .normal)
                }
                return cell
            case CONTENT_SECTION_GOOGLE:
                let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath) as! UserCell
                cell.titleLabel.text = "Google \"\(self.searchField.text ?? "")\""
                cell.profileImageView.image = #imageLiteral(resourceName: "search")
                return cell
            case CONTENT_SECTION_TAG:
                let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath) as! UserCell
                let text = (self.searchField.text ?? "").replacingOccurrences(of: " ", with: "").lowercased()
                cell.titleLabel.text = text.hasPrefix("#") ? text : "#\(text)"
                cell.profileImageView.image = #imageLiteral(resourceName: "hashtag")
                return cell
            case CONTENT_SECTION_RESULT:
                let cell = tableView.dequeueReusableCell(withIdentifier: self.searchContentSection.cellReuseIdentifier, for: indexPath)
                self.searchContentSection.populateCell(indexPath.row, cell: cell)
                return cell
            default:
                return UITableViewCell()
            }
        default:
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch tableView {
        case self.searchAccountsTable:
            switch indexPath.section {
            case USER_SECTION_INVITE:
                return 55
            case USER_SECTION_RESULT:
                return self.searchAccountsSection.rowHeight
            default:
                return 0
            }
        case self.searchAccountsVipTable:
            switch indexPath.section {
            case 0:
                return self.searchAccountsVipSection.rowHeight
            default:
                return 0
            }
        case self.searchContentTable:
            switch indexPath.section {
            case CONTENT_SECTION_GOOGLE, CONTENT_SECTION_TAG:
                return 65
            case CONTENT_SECTION_SUGGESTIONS, CONTENT_SECTION_RESULT:
                return self.searchContentSection.rowHeight
            default:
                return 0
            }
        default:
            return 0
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        switch scrollView {
        case self.containerScrollView:
            self.endEditing(true)
            let c = self.searchSegmentedControl!
            c.selectedSegmentIndex = max(0, min(c.numberOfSegments - 1, Int(scrollView.contentOffset.x / self.bounds.width + 0.5)))
        default:
            break
        }
    }

    // MARK: - Private

    private var contentSuggestions = [ContentResult]()
    private var importAlert: ConversationImportAlert?

    private var isSearching: Bool {
        return !(self.searchField.text?.isEmpty ?? true)
    }

    private var searchAccountsSection: SearchUserSection!
    private var searchAccountsVipSection: SearchUserSection!
    private var searchContentSection: SearchTopicSection!

    private func configureSegments(segments: [String]) {
        let c = self.searchSegmentedControl!
        while c.numberOfSegments < segments.count {
            c.insertSegment(withTitle: "", at: c.numberOfSegments, animated: false)
        }
        while c.numberOfSegments > segments.count {
            c.removeSegment(at: c.numberOfSegments - 1, animated: false)
        }
        segments.enumerated().forEach {
            c.setTitle($0.element, forSegmentAt: $0.offset)
        }
    }

    private func search() {
        guard var query = self.searchField.text?.trimmingCharacters(in: .whitespaces) else {
            return
        }
        if query.hasPrefix("#") {
            query.remove(at: query.startIndex)
            self.containerScrollView.setContentOffset(.zero, animated: false)
            self.searchField.becomeFirstResponder()
            self.searchSegmentedControl.selectedSegmentIndex = 0
        } else if query.hasPrefix("@") {
            query.remove(at: query.startIndex)
            self.containerScrollView.setContentOffset(CGPoint(x: self.bounds.width, y: 0), animated: false)
            self.searchField.becomeFirstResponder()
            self.searchSegmentedControl.selectedSegmentIndex = self.searchSegmentedControl.numberOfSegments - 1
        }
        guard !query.isEmpty else {
            return
        }
        if self.delegate?.searchViewShouldShowAccounts(self) ?? true {
            self.searchAccountsSection.search(query)
        }
        if self.delegate?.searchViewShouldShowAccountsVip(self) ?? true {
            self.searchAccountsVipSection.search(query)
        }
        self.searchContentSection.search(query)
    }
}

// TODO: Have search result and user result objects
struct UserResult {
    var accountId: Int64?
    var displayName: String?
    var identifier: String
    var imageURL: URL?
}

extension UserResult: Equatable {
    public static func ==(lhs: UserResult, rhs: UserResult) -> Bool {
        // Compare identifers only if neither side has an accountId
        guard lhs.accountId != nil || rhs.accountId != nil else {
            return lhs.identifier == rhs.identifier
        }
        return lhs.accountId == rhs.accountId
    }
}

class SearchResultCell: SeparatorCell {
    @IBOutlet weak var contentSuggestionView: ContentSuggestionView!
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        self.contentSuggestionView.thumbnailButton.isHighlighted = highlighted
    }
    
    override func prepareForReuse() {
        self.contentSuggestionView.thumbnailButton.setImage(nil, for: .normal)
        self.contentSuggestionView.titleLabel.text = nil
    }
}
