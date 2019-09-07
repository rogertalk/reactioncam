import UIKit

fileprivate let SECTION_ACCOUNTS = 0
fileprivate let SECTION_LOADING = 1

class AccountListViewController: UIViewController,
    UITableViewDelegate,
    UITableViewDataSource
{
    enum ListType {
        case none
        case followers(account: Account)
        case following(account: Account)
    }

    @IBOutlet weak var accountsTable: UITableView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var countLabel: UILabel!

    private(set) var accounts: [AccountWithFollowState] = []
    var cursor: String?
    var type: ListType = .none {
        didSet {
            self.accounts = []
            self.cursor = nil
            self.accountsTable?.reloadData()
            self.isLoading = false
            self.updateTitleLabel()
        }
    }

    private(set) var isLoading = false {
        didSet {
            guard oldValue != self.isLoading else {
                return
            }
            let indexPath = IndexPath(row: 0, section: SECTION_LOADING)
            if self.isLoading {
                self.accountsTable?.insertRows(at: [indexPath], with: .bottom)
            } else {
                self.accountsTable?.deleteRows(at: [indexPath], with: .fade)
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Logging.log("Account List Shown", ["Type": self.logType])

        self.accountsTable.delegate = self
        self.accountsTable.dataSource = self
        self.accountsTable.register(UINib(nibName: "UserCell", bundle: nil),
                                    forCellReuseIdentifier: "UserCell")

        self.updateTitleLabel()
        self.loadNextPage()
    }

    // MARK: - Actions

    @IBAction func backTapped(_ sender: Any) {
        Logging.debug("Account List Action", ["Action": "Back"])
        self.navigationController?.popViewController(animated: true)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.contentOffset.y > scrollView.contentSize.height - scrollView.frame.height else {
            return
        }
        // The last full page of the scroll view is visible.
        self.loadNextPage()
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case SECTION_ACCOUNTS:
            let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath) as! UserCell
            cell.user = self.accounts[indexPath.row]
            cell.followButton.isHidden = false
            return cell
        case SECTION_LOADING:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LoadingCell", for: indexPath)
            (cell.viewWithTag(1) as? UIActivityIndicatorView)?.startAnimating()
            return cell
        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case SECTION_ACCOUNTS:
            return self.accounts.count
        case SECTION_LOADING:
            return self.isLoading ? 1 : 0
        default:
            return 0
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let cell = tableView.cellForRow(at: indexPath) as? UserCell, let account = cell.user else {
            return
        }
        TabBarController.select(account: account)

        Logging.log("Account List Selection", [
            "Index": indexPath.row,
            "Username": account.username])
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    // MARK: - Private

    private var logType: String {
        switch self.type {
        case let .followers(account):
            return account.isCurrentUser ? "Own Followers" : "Other Followers"
        case let .following(account):
            return account.isCurrentUser ? "Own Following" : "Other Following"
        case .none:
            return "Unknown"
        }
    }

    private var requestCounter = 0

    private func loadNextPage() {
        let endMarker = "REACHED_END"
        guard !self.isLoading && self.cursor != endMarker else {
            return
        }
        let intent: Intent
        switch self.type {
        case let .followers(account):
            intent = .getFollowers(identifier: String(account.id), limit: nil, cursor: self.cursor)
        case let .following(account):
            intent = .getFollowing(identifier: String(account.id), limit: nil, cursor: self.cursor)
        case .none:
            return
        }
        self.isLoading = true
        self.requestCounter += 1
        let expectedCounterValue = self.requestCounter
        intent.perform(BackendClient.api) {
            guard self.requestCounter == expectedCounterValue else {
                return
            }
            guard $0.successful, let data = $0.data, let dataList = data["data"] as? [DataType] else {
                self.isLoading = false
                return
            }
            self.cursor = data["cursor"] as? String ?? endMarker
            let accounts: [AccountWithFollowState] = dataList.map(Profile.init(data:))
            guard accounts.count > 0 else {
                self.isLoading = false
                return
            }
            let c = self.accounts.count
            self.accounts += accounts
            let indexPaths = (c..<c + accounts.count).map { IndexPath(row: $0, section: SECTION_ACCOUNTS) }
            // Animate in the rows then show scroll indicator.
            CATransaction.begin()
            self.accountsTable.beginUpdates()
            CATransaction.setCompletionBlock {
                // The content size of the scroll view isn't recalculated until after this block.
                DispatchQueue.main.async {
                    self.accountsTable.flashScrollIndicators()
                    self.isLoading = false
                }
            }
            self.accountsTable.insertRows(at: indexPaths, with: c == 0 ? .none : .top)
            self.accountsTable.endUpdates()
            CATransaction.commit()
        }
    }

    private func updateTitleLabel() {
        guard let label = self.titleLabel else {
            return
        }
        switch self.type {
        case .none:
            label.text = ""
            self.countLabel.isHidden = true
        case let .followers(account):
            var suffix = "Subscribers"
            if let account = account as? AccountWithExtras, let followersTitle = account.properties["followers_title"] as? String, !followersTitle.isEmpty {
                suffix = followersTitle
            }
            label.text = "@\(account.username)‘" + (account.username.hasSuffix("s") ? " " : "s ") + suffix
            self.countLabel.text = "\(account.followerCount.formattedWithSeparator) subscribers"
        case let .following(account):
            label.text = account.isCurrentUser ? "My Subscriptions" : "@\(account.username)‘" + (account.username.hasSuffix("s") ? " " : "s ") + "Subscriptions"
            self.countLabel.text = "\(account.followingCount.formattedWithSeparator) channels"
        }
    }
}
