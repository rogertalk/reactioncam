import StoreKit
import UIKit

class RewardsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    @IBOutlet weak var backgroundView: UIView!
    @IBOutlet weak var coinsLabel: UILabel!
    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var userBackgroundImageView: UIImageView!
    @IBOutlet weak var creatorLabel: UILabel!
    @IBOutlet weak var editButton: UIButton!
    @IBOutlet weak var rewardsTable: UITableView!

    var account: AccountWithExtras?

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.insertSubview(self.cheerView, aboveSubview: self.backgroundView)
        self.cheerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.cheerView.frame = self.view.bounds
        let cheerImages = [#imageLiteral(resourceName: "coin1"), #imageLiteral(resourceName: "coin2"), #imageLiteral(resourceName: "coin1"), #imageLiteral(resourceName: "coin2"), #imageLiteral(resourceName: "coin3"), #imageLiteral(resourceName: "coin4"), #imageLiteral(resourceName: "coin5")]
        self.cheerView.config.particle = .image(cheerImages)
        self.cheerView.config.colors = cheerImages.map { _ in .white }
        self.cheerView.config.customize = { emitter, cells in
            emitter.renderMode = kCAEmitterLayerUnordered
            cells.forEach {
                $0.birthRate = 13
                $0.blueRange = 0
                $0.greenRange = 0
                $0.redRange = 0
                $0.scale = 0.2
                $0.scaleRange = 0.1
                $0.spinRange = 15
            }
        }
        self.cheerView.alpha = 0
        self.cheerView.start()

        self.rewardsTable.delegate = self
        self.rewardsTable.dataSource = self
        self.rewardsTable.rowHeight = UITableViewAutomaticDimension
        self.rewardsTable.register(UINib(nibName: "RewardCell", bundle: nil), forCellReuseIdentifier: "RewardCell")
        self.rewardsTable.register(UINib(nibName: "SendGiftCell", bundle: nil), forCellReuseIdentifier: "SendGiftCell")
        self.rewardsTable.register(UINib(nibName: "TipCell", bundle: nil), forCellReuseIdentifier: "TipCell")
        self.rewardsTable.register(UINib(nibName: "UserCell", bundle: nil), forCellReuseIdentifier: "UserCell")

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(RewardsViewController.handleTap)))

        PaymentService.instance.purchaseDidComplete.addListener(self, method: RewardsViewController.handlePurchaseDidComplete)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.refresh()
        guard let id = self.account?.id else {
            return
        }
        Intent.getProfileTopPayers(identifier: String(id)).perform(BackendClient.api) {
            guard $0.successful, let data = $0.data?["data"] as? [DataType] else {
                return
            }
            let contribs: [(Account, Int)] = data.compactMap {
                guard
                    let accountData = $0["account"] as? DataType,
                    let amount = $0["total_amount"] as? Int
                    else { return nil }
                let account = AccountBase(data: accountData)
                return (account, amount)
            }
            self.contributions = Array(contribs.prefix(3))
            self.rewardsTable?.reloadData()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return self.contributions.count
        case 1:
            return 1
        case 2:
            return self.rewards.count
        case 3:
            return 1
        default:
            return 0
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath) as! UserCell
            let contribution = self.contributions[indexPath.row]
            cell.user = contribution.0
            cell.voteCountLabel.text = "\(contribution.1) 💰"
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TipCell", for: indexPath)
            return cell
        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "RewardCell", for: indexPath) as! RewardCell
            let reward = self.rewards[indexPath.row]
            if let coins = reward["coins"] as? Int {
                cell.coinLabel.text = "\(coins) \(coins == 1 ? "Coin" : "Coins")"
            } else {
                cell.coinLabel.text = "--"
            }
            cell.titleLabel.text = reward["title"] as? String ?? "--"
            cell.rewardLabel.text = reward["description"] as? String ?? "No description."
            return cell
        case 3:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SendGiftCell", for: indexPath)
            return cell
        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, estimatedRowHeight indexPath: IndexPath) -> CGFloat {
        return 65
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return indexPath.section == 0 ? 65 : UITableViewAutomaticDimension
    }

    private var tipTimer: Timer?

    @objc private dynamic func sendTip(timer: Timer) {
        guard let amount = timer.userInfo as? Int else {
            return
        }
        timer.invalidate()
        self.tipTimer = nil
        self.sendCoins(amount: amount, comment: "Tip 👍", showFeedback: false)
        Logging.log("Send Coins", [
            "Type": "Tip",
            "Value": String(amount),
            "Result": "Success"])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !(self.account?.isCurrentUser ?? true) else {
            let alert = UIAlertController(title: "Oops! 😄", message: "You cannot send Coins to yourself.", preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
            return
        }
        guard let session = BackendClient.api.session else {
            return
        }
        switch indexPath.section {
        case 0:
            TabBarController.select(account: self.contributions[indexPath.row].0)
        case 1:
            let amount = 1
            guard session.balance >= amount else {
                let error = UIAlertController(title: "Not enough Coins 🤑", message: "Try getting more.", preferredStyle: .alert)
                error.addCancel(title: "OK") {
                    self.showBuyCoins()
                }
                Logging.log("Send Coins", [
                    "Type": "Tip",
                    "Value": String(amount),
                    "Result": "NotEnough"])
                self.present(error, animated: true)
                return
            }

            // Pool tips and send in batches
            let total = (self.tipTimer?.userInfo as? Int ?? 0) + 1
            self.tipTimer?.invalidate()
            self.tipTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(RewardsViewController.sendTip), userInfo: total, repeats: false)

            self.cheerView.showAnimated()

            guard let contentView = tableView.cellForRow(at: indexPath)?.contentView else {
                return
            }

            // Shoot the label right in a random direction.
            let tipLabel = UILabel()
            tipLabel.frame = contentView.bounds
            tipLabel.textAlignment = .center
            tipLabel.textColor = .uiYellow
            tipLabel.font = .systemFont(ofSize: 16, weight: .bold)
            tipLabel.text = "+1!"
            contentView.addSubview(tipLabel)
            UIView.animate(withDuration: 0.4, delay: 0.0, options: .curveEaseOut, animations: {
                tipLabel.transform = CGAffineTransform(scaleX: 1, y: 1).translatedBy(x: 100, y: CGFloat(arc4random_uniform(60)) - 30)
            }, completion: { _ in
                tipLabel.hideAnimated {
                    tipLabel.removeFromSuperview()
                }
            })
        case 2:
            let reward = self.rewards[indexPath.row]
            guard let amount = reward["coins"] as? Int else {
                return
            }
            guard session.balance >= amount else {
                let alert = UIAlertController(title: "Not enough Coins 🤑", message: "You don't have enough Coins for this reward. Try getting more!", preferredStyle: .alert)
                alert.addCancel(title: "OK") {
                    self.showBuyCoins()
                }
                self.present(alert, animated: true)
                Logging.log("Send Coins", [
                    "Type": "Reward",
                    "Value": String(amount),
                    "Result": "NotEnough"])
                return
            }

            let confirm = UIAlertController(title: "Send \(amount) \(amount == 1 ? "Coin" : "Coins")?", message: nil, preferredStyle: .alert)
            confirm.addAction(UIAlertAction(title: "Yes! 😄", style: .default) { _ in
                Logging.log("Send Coins", [
                    "Type": "Reward",
                    "Value": String(amount),
                    "Result": "Success"])
                self.sendCoins(amount: amount, comment: reward["title"] as? String)
            })
            confirm.addCancel() {
                Logging.log("Send Coins", [
                    "Type": "Reward",
                    "Value": String(amount),
                    "Result": "Cancelled"])
            }
            self.present(confirm, animated: true)
        case 3:
            let alert = UIAlertController(title: "Gift Coins", message: "Send this creator some coins with a comment 🤗.", preferredStyle: .alert)
            alert.addTextField(configurationHandler: { textField in
                textField.keyboardAppearance = .dark
                textField.keyboardType = .numberPad
                textField.placeholder = "Coins"
                textField.returnKeyType = .done
            })
            alert.addTextField(configurationHandler: { textField in
                textField.keyboardAppearance = .dark
                textField.keyboardType = .default
                textField.placeholder = "Comment"
                textField.returnKeyType = .done
                textField.delegate = self
            })
            alert.addAction(UIAlertAction(title: "Send", style: .default) { _ in
                guard let amount = alert.textFields?.first?.text?.intValue else {
                    return
                }
                guard session.balance >= amount else {
                    let error = UIAlertController(title: "Not enough Coins 🤑", message: "You don't have enough Coins to send this many.", preferredStyle: .alert)
                    error.addCancel(title: "OK")
                    Logging.log("Send Coins", [
                        "Type": "Gift",
                        "Value": String(amount),
                        "Result": "NotEnough"])
                    self.present(error, animated: true)
                    return
                }
                Logging.log("Send Coins", [
                    "Type": "Gift",
                    "Value": String(amount),
                    "Result": "Success"])
                self.sendCoins(amount: amount, comment: alert.textFields?[1].text)
            })
            alert.addCancel()
            self.present(alert, animated: true)
        default:
            return
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 0:
            return self.contributions.isEmpty ? 0.001 : 50
        case 1:
            return 50
        default:
            return 0.001
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header: String
        switch section {
        case 0:
            guard !self.contributions.isEmpty else {
                return nil
            }
            header = "TOP SUPPORTERS"
        case 1:
            header = "REWARDS"
        default:
            return nil
        }

        let headerView = UIView()
        headerView.frame = CGRect(x: 0, y: 0, width: tableView.frame.width, height: 50)
        headerView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        let textLabel = UILabel(frame: headerView.bounds.offsetBy(dx: 18, dy: 0))
        textLabel.font = UIFont.systemFont(ofSize: 16)
        textLabel.textColor = .lightText
        textLabel.text = header
        headerView.addSubview(textLabel)
        return headerView
    }

    @IBAction func coinsTapped(_ sender: Any) {
        self.showBuyCoins()
    }

    @IBAction func editRewardsTapped(_ sender: Any) {
        guard let editRewards = Bundle.main.loadNibNamed("EditRewardsViewController", owner: nil, options: nil)?.first as? EditRewardsViewController else {
            return
        }
        self.present(editRewards, animated: true)
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Limit text input to 60 characters
        return string.isEmpty || range.length + range.location < 60
    }

    // MARK: - Private

    private let cheerView = CheerView()
    private var contributions = [(Account, Int)]()
    private var rewards = [[String: Any]]()
    private var statusIndicatorView: StatusIndicatorView!

    private func handlePurchaseDidComplete() {
        self.refresh()
    }

    @objc private dynamic func handleTap() {
        self.dismiss(animated: true)
    }

    private func refresh() {
        let isCurrentUser = self.account?.isCurrentUser ?? true
        if isCurrentUser {
            // Get latest data from session
            self.account = BackendClient.api.session
            self.creatorLabel.isHidden = true
            self.userImageView.isHidden = true
            self.editButton.isHidden = false
        } else {
            self.creatorLabel.text = self.account!.username
            self.creatorLabel.isHidden = false
            self.editButton.isHidden = true
        }
        if let url = self.account?.imageURL {
            self.userImageView.af_setImage(withURL: url, placeholderImage: UIImage(named: "single"))
            self.userBackgroundImageView.af_setImage(withURL: url, placeholderImage: UIImage(named: "single"))
        }
        if let tiers = self.account?.properties["tiers"] as? [[String: Any]] {
            self.rewards = tiers
            self.rewardsTable.reloadData()
        }
        if let balance = BackendClient.api.session?.balance {
            self.coinsLabel.text = "\(balance) Coins"
        } else {
            self.coinsLabel.text = "--"
        }
    }

    private func sendCoins(amount: Int, comment: String?, showFeedback: Bool = true) {
        guard let account = self.account else {
            return
        }
        if showFeedback {
            self.statusIndicatorView.showLoading()
        }
        Intent.pay(identifier: String(account.id), amount: amount, comment: comment).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            guard $0.successful else {
                let alert = UIAlertController(
                    title: "Oops!",
                    message: "Something went wrong. Please try again later.",
                    preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            self.refresh()
            self.cheerView.showAnimated()
            if showFeedback {
                let alert = UIAlertController(
                    title: "Success 😃",
                    message: "Your Coins were sent, @\(account.username) will be notified!\n\nThank you for your support.",
                    preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
            }
        }
    }

    private func showBuyCoins() {
        Logging.log("Buy Coins Shown", ["Source": "Rewards"])
        PaymentService.instance.showBuyCoins()
    }
}

class RewardCell: SeparatorCell {
    @IBOutlet weak var coinLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var rewardLabel: UILabel!
}
