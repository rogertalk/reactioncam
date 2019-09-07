import UIKit

class SimilarCreatorsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak var followButton: HighlightButton!
    @IBOutlet weak var similarCreatorsTableView: UITableView!
    
    var similarCreators = [Account]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.similarCreatorsTableView.register(UINib(nibName: "SimilarCreatorCell", bundle: nil), forCellReuseIdentifier: "SimilarCreatorCell")
        self.similarCreatorsTableView.dataSource = self
        self.similarCreatorsTableView.delegate = self
        self.similarCreatorsTableView.rowHeight = 60
        self.similarCreatorsTableView.delaysContentTouches = false
        (self.similarCreatorsTableView.subviews.first as? UIScrollView)?.delaysContentTouches = false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        // Preselect everything the first time this screen is entered
        if !self.didSelectAllOnce {
            self.didSelectAllOnce = true
            self.similarCreatorsTableView.reloadData()
            for row in 0..<self.similarCreatorsTableView.numberOfRows(inSection: 0) {
                self.similarCreatorsTableView.selectRow(at: IndexPath(row: row, section: 0) as IndexPath, animated: true, scrollPosition: .none)
                
            }
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    @IBAction func followSimilarCreatorsTapped(_ sender: Any) {
        guard let selected = self.similarCreatorsTableView.indexPathsForSelectedRows else {
            return
        }
        let identifiers: [Int64] = selected.compactMap {
            self.similarCreators[$0.row].id
        }
        FollowService.instance.follow(ids: identifiers)

        Logging.log("Subscribe Similar Creators", ["Count": identifiers.count])
        
        let alert = UIAlertController(title: "Subscribed!", message: nil, preferredStyle: .alert)
        alert.addCancel(title: "OK") {
            self.dismiss(animated: true)
        }
        self.present(alert, animated: true)
    }
    
    @IBAction func closeTapped(_ sender: Any) {
        self.navigationController?.popViewControllerModal()
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.similarCreators.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SimilarCreatorCell", for: indexPath) as! SimilarCreatorCell
        let account = self.similarCreators[indexPath.row]
        cell.account = account
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? SimilarCreatorCell else {
            return
        }
        cell.isSelected = true
        self.followButton.setTitle("Subscribe (\(tableView.indexPathsForSelectedRows?.count ?? 0))", for: .normal)
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? SimilarCreatorCell else {
            return
        }
        cell.isSelected = false
        self.followButton.setTitle("Subscribe (\(tableView.indexPathsForSelectedRows?.count ?? 0))", for: .normal)
    }
    
    private var didSelectAllOnce = false
}

class SimilarCreatorCell: SeparatorCell {
    @IBOutlet weak var creatorImageView: UIImageView!
    @IBOutlet weak var usernameButton: UIButton!
    @IBOutlet weak var toggleLabel: UILabel!
    
    var account: Account? {
        didSet {
            guard let account = self.account else {
                self.creatorImageView.af_cancelImageRequest()
                self.creatorImageView.image = #imageLiteral(resourceName: "single")
                self.toggleLabel.text = "radio_button_unchecked"
                self.usernameButton.setTitle(nil, for: .normal)
                return
            }
            if let url = account.imageURL {
                self.creatorImageView.af_setImage(withURL: url)
            }
            self.usernameButton.setTitle(account.username, for: .normal)
        }
    }
    
    override var isSelected: Bool {
        didSet {
            self.toggleLabel.text = self.isSelected ? "radio_button_checked" : "radio_button_unchecked"
        }
    }
    
    override func awakeFromNib() {
        let highlightView = UIView()
        highlightView.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        self.selectedBackgroundView = highlightView
    }
    
    override func prepareForReuse() {
        self.account = nil
    }
    
    @IBAction func usernameTapped(_ sender: Any) {
        guard let account = self.account else {
            return
        }
        TabBarController.select(account: account)
    }
}
