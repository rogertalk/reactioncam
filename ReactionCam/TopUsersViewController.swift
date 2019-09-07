import UIKit

class TopUsersViewController: UIViewController,
    UIScrollViewDelegate,
    UITableViewDelegate
{

    let firstData = TopUsersDataSource(intent: Intent.getTopAccountsByFirst())
    let paymentsData = TopUsersDataSource(intent: Intent.getTopAccountsByPaymentsReceived())

    @IBOutlet weak var firstTable: UITableView!
    @IBOutlet weak var pageControl: UIPageControl!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var votesTable: UITableView!

    override var prefersStatusBarHidden: Bool {
        return false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Logging.log("Top Users Shown")

        self.scrollView.delegate = self

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.statusIndicatorView.showLoading()

        self.votesTable.delegate = self
        self.votesTable.dataSource = self.paymentsData
        self.votesTable.register(UINib(nibName: "UserCell", bundle: nil), forCellReuseIdentifier: "UserCell")
        paymentsData.load { _ in
            self.statusIndicatorView.hide()
            self.votesTable.reloadData()
        }

        self.firstTable.delegate = self
        self.firstTable.dataSource = self.firstData
        self.firstTable.register(UINib(nibName: "UserCell", bundle: nil), forCellReuseIdentifier: "UserCell")
        firstData.load { _ in
            self.firstTable.reloadData()
        }
    }

    // MARK: - Actions

    @IBAction func backTapped(_ sender: Any) {
        Logging.debug("Top Users Action", ["Action": "Back"])
        self.navigationController?.popViewController(animated: true)
    }

    @IBAction func pageChanged(_ sender: UIPageControl) {
        let offset = CGPoint(x: scrollView.frame.width * CGFloat(sender.currentPage), y: 0)
        self.scrollView.setContentOffset(offset, animated: true)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView == self.scrollView else { return }
        self.pageControl.currentPage = Int(scrollView.contentOffset.x / scrollView.frame.width)
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let cell = tableView.cellForRow(at: indexPath) as? UserCell, let account = cell.user else {
            return
        }
        TabBarController.select(account: account)

        Logging.log("Top User Selection", [
            "Index": indexPath.row,
            "Username": account.username])
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    // MARK: - Private

    private var statusIndicatorView: StatusIndicatorView!
}

class TopUsersDataSource: NSObject, UITableViewDataSource {
    let intent: Intent

    private(set) var list = [(account: Account, score: Int)]()

    init(intent: Intent) {
        self.intent = intent
    }

    func load(completionHandler callback: @escaping (Bool) -> Void) {
        self.intent.perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                callback(false)
                return
            }
            self.list = data.compactMap {
                guard let account = $0["account"] as? DataType, let score = $0["score"] as? Int else {
                    return nil
                }
                return (AccountBase(data: account), score)
            }
            callback(true)
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath) as! UserCell
        let info = self.list[indexPath.row]
        cell.user = info.account
        cell.rank = indexPath.row + 1
        switch self.intent {
        case .getTopAccountsByFirst:
            cell.voteCountLabel.text = "\(info.score) 💎"
        case .getTopAccountsByPaymentsReceived:
            cell.voteCountLabel.text = "\(info.score) 💰"
        default:
            cell.voteCountLabel.text = String(info.score)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.list.count
    }
}
