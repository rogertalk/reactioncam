import UIKit

fileprivate let HEADER_HEIGHT = 126.0
fileprivate let SECTION_CONTENT = 0
fileprivate let SECTION_LOADING = 1

class DiscoverViewController: UIViewController,
    ConversationImportDelegate,
    SearchViewDelegate,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UITableViewDataSource,
    UITableViewDelegate,
    UITextFieldDelegate
{

    @IBOutlet weak var addButton: CameraControlButton!
    @IBOutlet weak var addUsersTable: UITableView!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var featuredCollectionView: UICollectionView!
    @IBOutlet weak var regionButton: UIButton!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.searchView.refreshSubscriptions()
        if !self.searchView.isHidden {
            self.searchView.searchField.becomeFirstResponder()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.addUsersTable.delegate = self
        self.addUsersTable.dataSource = self
        self.addUsersTable.contentInset = UIEdgeInsets(top: CGFloat(HEADER_HEIGHT), left: 0, bottom: 0, right: 0)
        self.addUsersTable.keyboardDismissMode = .onDrag
        self.addUsersTable.register(UINib(nibName: "TopContentCell", bundle: nil), forCellReuseIdentifier: "TopContentCell")

        self.refreshControl.tintColor = .white
        self.refreshControl.addTarget(self, action: #selector(DiscoverViewController.refreshPulled), for: .valueChanged)
        self.addUsersTable.refreshControl = self.refreshControl

        self.featuredCollectionView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        self.featuredCollectionView.delegate = self
        self.featuredCollectionView.dataSource = self
        self.featuredCollectionView.register(UINib(nibName: "ContentGridCell", bundle: nil), forCellWithReuseIdentifier: "ContentGridCell")

        self.updateFeatured()
        ContentService.instance.featuredContentChanged.addListener(self, method: DiscoverViewController.updateFeatured)

        self.loadContent()

        if Recorder.instance.composer != nil && SettingsManager.shouldShowNewBadge(for: "plus_button") {
            TabBarController.instance?.tooltip.show()
        }

        let searchView = Bundle.main.loadNibNamed("SearchView", owner: nil, options: nil)?.first as! SearchView
        searchView.delegate = self
        searchView.frame = self.view.bounds
        searchView.isHidden = true
        searchView.presenter = self
        self.view.addSubview(searchView)
        self.searchView = searchView

        self.dateLabel.text = Date().dateLabel.uppercased()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.searchView.frame = self.view.bounds
    }

    func scrollToTop() {
        self.addUsersTable.setContentOffset(CGPoint(x: 0.0, y: -HEADER_HEIGHT), animated: true)
    }

    // MARK: - ConversationImportDelegate

    var conversationImportAnchorView: UIView {
        return self.addButton
    }

    // MARK: - SearchViewDelegate

    func searchView(_ view: SearchView, didSelect result: SearchView.Result) {
        switch result {
        case let .account(account):
            TabBarController.select(account: account)
        case let .content(content, source):
            TabBarController.select(originalContent: content, source: "Discover \(source)")
        case let .googleQuery(query):
            TabBarController.showCreate(url: query.searchURL(), ref: nil, relevantUsername: nil,
                                        source: "Discover Google Search")
        case let .tag(tag):
            TabBarController.select(tags: [tag])
        }
    }

    func searchViewShouldShowAccounts(_ view: SearchView) -> Bool {
        return true
    }

    func searchViewShouldShowAccountsVip(_ view: SearchView) -> Bool {
        return false
    }

    func searchViewShouldShowTags(_ view: SearchView) -> Bool {
        return true
    }

    // MARK: UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch indexPath.section {
        case 0:
            let content = ContentService.instance.featuredContent[indexPath.row]
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ContentGridCell", for: indexPath) as! ContentGridCell
            if let url = content.thumbnailURL {
                cell.thumbnailImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
            }
            cell.titleLabel.text = content.title ?? content.relatedTo?.title ?? ""
            return cell
        default:
            return collectionView.dequeueReusableCell(withReuseIdentifier: "MoreCell", for: indexPath)
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return section == 0 ? ContentService.instance.featuredContent.count : 1
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch indexPath.section {
        case 0:
            let content = ContentService.instance.featuredContent
            TabBarController.select(contentList: content, presetContentId: content[indexPath.row].id)
        default:
            self.selectTrendingTag()
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == self.addUsersTable else {
            return
        }
        // Load more if we are 4 screen heights away from the end.
        let section = self.topContentSection
        let offset = scrollView.contentOffset.y
        section.lastScrollOffset = offset
        guard section.cursor != nil,
            !self.isLoading &&
                offset > (scrollView.contentSize.height - scrollView.frame.size.height * 4) else {
                    return
        }
        self.loadContent()
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case SECTION_CONTENT:
            return self.topContent.count
        case SECTION_LOADING:
            return 1
        default:
            return 0
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case SECTION_CONTENT:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TopContentCell", for: indexPath) as! TopContentCell
            let content = self.topContent[indexPath.row]
            cell.originalContentView?.content = content
            cell.originalContentView?.source = "Discover"
            return cell
        case SECTION_LOADING:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LoadingCell", for: indexPath)
            (cell.viewWithTag(1) as? UIActivityIndicatorView)?.startAnimating()
            return cell
        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case SECTION_CONTENT:
            return OriginalContentView.defaultHeight
        default:
            return 65
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == SECTION_CONTENT && indexPath.row < self.topContent.count else {
            return
        }
        TabBarController.select(originalContent: self.topContent[indexPath.row], source: "Discover Row")
        Logging.log("Search Tab Action", [
            "Source": self.topContentSection.displayName,
            "Index": String(indexPath.row)]
        )
    }

    // MARK: - Actions

    @IBAction func addTapped(_ sender: UIButton) {
        let alert = ConversationImportAlert(title: "See your friends reactions to videos\nand show them your channel! 👯", message: nil, source: "Search", importActions: [.invite], owner: self, delegate: self)
        alert.show()
        self.importAlert = alert
    }

    @IBAction func regionButtonTapped(_ sender: Any) {
        Logging.log("Search Tab Action", ["Action": "Change Region"])
        self.regionButton.pulse()
    }

    @IBAction func searchTapped(_ sender: Any) {
        self.searchView.show()
    }

    @IBAction func topRewardsTapped(_ sender: Any) {
        Logging.log("Top Rewards Tapped", ["Source": "Search"])
        guard let topRewards = Bundle.main.loadNibNamed("TopRewardsViewController", owner: nil, options: nil)?.first as? TopRewardsViewController else {
            return
        }
        self.navigationController?.pushViewController(topRewards, animated: true)
    }

    @IBAction func trendingTagTapped(_ sender: Any) {
        self.selectTrendingTag()
    }

    // MARK: - Private

    private let refreshControl = UIRefreshControl()
    private let topContentSection = TagSection(displayName: "TRENDING NOW", tag: "original", sort: "hot")

    private var importAlert: ConversationImportAlert?
    private var isLoading = false
    private var searchView: SearchView!
    private var statusIndicatorView: StatusIndicatorView!

    private var featuredUsers = [Account]() {
        didSet {
            self.addUsersTable.reloadData()
        }
    }

    private var topContent = [OriginalContent]() {
        didSet {
            self.addUsersTable.reloadData()
        }
    }

    private func selectTrendingTag() {
        TabBarController.select(tags: ["featured"], title: "#featured")
        Logging.log("Trending Tag Tapped", ["Tag": "#featured"])
    }
    
    @objc private dynamic func refreshPulled(_ sender: UIRefreshControl) {
        self.loadContent(reset: true) { _ in
            sender.endRefreshing()
        }
    }

    private func updateFeatured() {
        var users = [Account]()
        for content in ContentService.instance.featuredContent.sorted(by: { return $0.votes > $1.votes }) {
            guard !users.contains(where: { $0.id == content.creatorId }) else { continue }
            users.append(content.creator)
        }
        self.featuredUsers = users
        self.featuredCollectionView.reloadData()
    }

    private func loadContent(reset: Bool = false, completionHandler: ((Bool) -> ())? = nil) {
        let section = self.topContentSection
        self.isLoading = true
        Intent.getOriginalContentList(sortBy: section.sort, limit: 10, cursor: reset ? nil : section.cursor).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            self.isLoading = false
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                completionHandler?(false)
                return
            }
            var content: [OriginalContent]
            if let existingContent = section.content, !reset {
                content = existingContent
            } else {
                content = []
            }
            content.append(contentsOf: data.compactMap(OriginalContent.init))
            section.content = content
            section.cursor = $0.data?["cursor"] as? String
            self.topContent = content
            completionHandler?(true)
        }
    }
}

class TagSection: Equatable {
    let displayName: String
    let sort: String
    let tag: String

    var content: [OriginalContent]?
    var cursor: String?
    var lastScrollOffset: CGFloat = 0

    init(displayName: String, tag: String, sort: String) {
        self.displayName = displayName
        self.tag = tag
        self.sort = sort
    }

    static func ==(lhs: TagSection, rhs: TagSection) -> Bool {
        return lhs.tag == rhs.tag && lhs.sort == rhs.sort
    }

    func reset() {
        self.content = nil
        self.cursor = nil
        self.lastScrollOffset = 0
    }
}

class TopContentCell: UITableViewCell {
    @IBOutlet weak var originalContentView: OriginalContentView!
    
    override func prepareForReuse() {
        self.originalContentView.content = nil
    }
}
