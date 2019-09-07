import UIKit

class TopRewardsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet weak var rewardsTable: UITableView!
    @IBOutlet weak var transactionFeedTable: UITableView!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.rewardsTable.contentInset =
            UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        self.rewardsTable.delegate = self
        self.rewardsTable.dataSource = self
        self.rewardsTable.rowHeight = UITableViewAutomaticDimension
        self.rewardsTable.estimatedRowHeight = 100
        self.rewardsTable.register(UINib(nibName: "TopRewardCell", bundle: nil), forCellReuseIdentifier: "TopRewardCell")

        self.transactionFeedTable.contentInset =
            UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        self.transactionFeedTable.delegate = self
        self.transactionFeedTable.dataSource = self
        self.transactionFeedTable.rowHeight = UITableViewAutomaticDimension
        self.transactionFeedTable.estimatedRowHeight = 100
        self.transactionFeedTable.register(UINib(nibName: "TransactionCell", bundle: nil), forCellReuseIdentifier: "TransactionCell")

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        
        let getPaymentsFeed = Promise<Void>() { resolve, reject in
            Intent.getPaymentsFeed().perform(BackendClient.api) {
                self.statusIndicatorView.hide()
                guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                    resolve(())
                    return
                }
                self.transactions = data.compactMap(Transaction.init)
                self.transactionFeedTable.reloadData()
                resolve(())
            }
        }
        let getTopRewards = Promise<Void>() { resolve, reject in
            Intent.getTopRewards().perform(BackendClient.api) {
                guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                    resolve(())
                    return
                }
                self.rewards = data.compactMap(TopReward.init)
                self.rewardsTable.reloadData()
                resolve(())
            }
        }
        self.statusIndicatorView.showLoading()
        Promise.all([getPaymentsFeed, getTopRewards]).then { _ in
            DispatchQueue.main.async {
                self.statusIndicatorView.hide()
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    @IBAction func segmentedControlValueChanged(_ sender: Any) {
        let showFeed = self.segmentedControl.selectedSegmentIndex == 0
        self.rewardsTable.isHidden = showFeed
        self.transactionFeedTable.isHidden = !showFeed
    }
    
    @IBAction func backTapped(_ sender: Any) {
        self.navigationController?.popViewController(animated: true)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch tableView {
        case self.transactionFeedTable:
            return self.transactions.count
        default:
            return self.rewards.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch tableView {
        case self.transactionFeedTable:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TransactionCell", for: indexPath) as! TransactionCell
            let transaction = self.transactions[indexPath.row]
            if let url = transaction.sender.imageURL {
                cell.senderImageView.af_setImage(withURL: url)
            }
            cell.titleLabel.text = "@\(transaction.sender.username) gave \(transaction.amount) coins to @\(transaction.receiver.username)"
            cell.descriptionLabel.text = transaction.comment
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TopRewardCell", for: indexPath) as! TopRewardCell
            let reward = self.rewards[indexPath.row]
            cell.coinLabel.text = "\(reward.coins) Coins"
            cell.titleLabel.text = reward.title
            cell.descriptionLabel.text = reward.description
            cell.usernameLabel.text = reward.username
            if let url = reward.imageURL {
                cell.userImageView.af_setImage(withURL: url)
            }
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.statusIndicatorView.showLoading()
        Intent.getProfile(identifier: String(self.rewards[indexPath.row].accountId)).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            guard $0.successful, let data = $0.data else {
                return
            }
            let profile = Profile(data: data)
            TabBarController.select(account: profile)
            TabBarController.showRewards(for: profile)
        }
    }
    
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return tableView == self.rewardsTable
    }
    
    private var statusIndicatorView: StatusIndicatorView!
    private var rewards = [TopReward]()
    private var transactions = [Transaction]()

    struct TopReward {
        let accountId: Int64
        let coins: Int
        let description: String
        let imageURL: URL?
        let title: String
        let username: String
        
        init?(data: DataType) {
            guard let accountId = data["account_id"] as? Int64,
                let coins = data["coins"] as? Int,
                let description = data["description"] as? String,
                let title = data["title"] as? String,
                let username = data["username"] as? String else {
                    return nil
            }
            self.accountId = accountId
            self.coins = coins
            self.description = description
            self.title = title
            self.username = username
            if let urlString = data["image_url"] as? String {
                self.imageURL = URL(string: urlString)
            } else {
                self.imageURL = nil
            }
        }
    }
}

class TopRewardCell: SeparatorCell {
    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var usernameLabel: UILabel!
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var coinLabel: UILabel!
}

class TransactionCell: SeparatorCell {
    @IBOutlet weak var senderImageView: UIImageView!
    @IBOutlet weak var titleLabel: TagLabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.titleLabel.mentionColor = .uiYellow
    }
}

struct Transaction {
    let amount: Int
    let comment: String
    let receiver: TransactionParticipant
    let sender: TransactionParticipant
    
    init(data: DataType) {
        self.amount = data["amount"] as! Int
        self.comment = data["comment"] as? String ?? "Tip 👍"
        self.receiver = TransactionParticipant(data: data["receiver"] as! DataType)
        self.sender = TransactionParticipant(data: data["sender"] as! DataType)
    }
}

struct TransactionParticipant {
    let id: Int64
    let imageURL: URL?
    let username: String
    
    init(data: DataType) {
        self.id = data["id"] as! Int64
        self.imageURL = (data["image_url"] as? String).flatMap(URL.init(string:))
        self.username = data["username"] as! String
    }
}

