import UIKit

fileprivate let SECTION_COUNT = 3

fileprivate let SECTION_SUBMIT = 0
fileprivate let SECTION_EXPLANATION = 1
fileprivate let SECTION_REQUESTS = 2

class PublicRequestsViewController: UIViewController,
    OriginalPickerDelegate,
    SearchViewDelegate,
    SubmitRequestCellDelegate,
    UITableViewDataSource,
    UITableViewDelegate
{
    @IBOutlet weak var requestsTable: UITableView!

    private(set) var requests = [PublicContentRequest]() {
        didSet {
            self.requestsTable.reloadSections([SECTION_REQUESTS], with: .automatic)
        }
    }

    func scrollToTop() {
        self.requestsTable.scrollToTop()
    }

    // MARK: - UIViewController

    override var prefersStatusBarHidden: Bool {
        return false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidAppear(_ animated: Bool) {
        if self.requests.isEmpty && !self.isLoadingRequests {
            // Reload the requests if the list hasn't loaded.
            self.loadRequests(firstPage: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Add a search view for submitting requests.
        let searchView = Bundle.main.loadNibNamed("SearchView", owner: nil)?.first as! SearchView
        searchView.delegate = self
        searchView.frame = self.view.bounds
        searchView.isHidden = true
        searchView.presenter = self
        self.view.addSubview(searchView)
        self.searchView = searchView
        // Add a loading indicator to be used when performing backend calls.
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        // Set up the requests table appearance and delegates.
        self.requestsTable.contentInset = UIEdgeInsets(top: 80, left: 0, bottom: 0, right: 0)
        self.requestsTable.dataSource = self
        self.requestsTable.delegate = self
        // Add the pull-to-refresh control.
        self.requestsTableRefresh.tintColor = .white
        self.requestsTableRefresh.addTarget(self, action: #selector(PublicRequestsViewController.requestsTableRefreshPulled), for: .valueChanged)
        self.requestsTable.refreshControl = self.requestsTableRefresh
        // Load public requests.
        self.statusIndicatorView.showLoading()
        self.loadRequests(firstPage: true) { _ in
            self.statusIndicatorView.hideAnimated()
        }
    }

    // MARK: - OriginalPickerDelegate

    func originalPicker(_ picker: OriginalPickerViewController, didFinishPicking content: ContentRef) {
        picker.dismiss(animated: true)
        self.submitRequest(ref: content)
    }

    // MARK: - SearchView

    func searchView(_ view: SearchView, didSelect result: SearchView.Result) {
        view.endEditing(true)
        switch result {
        case let .googleQuery(query):
            let picker = self.storyboard?.instantiateViewController(withIdentifier: "OriginalPicker") as! OriginalPickerViewController
            picker.delegate = self
            if let url = query.searchURL() {
                picker.present(url: url)
            }
            self.present(picker, animated: true) {
                view.hideAnimated()
            }
        case let .content(result, _):
            self.submitRequest(ref: result.ref)
            view.hideAnimated()
        default:
            return
        }
    }

    func searchViewShouldShowAccounts(_ view: SearchView) -> Bool {
        return false
    }

    func searchViewShouldShowAccountsVip(_ view: SearchView) -> Bool {
        return false
    }

    func searchViewShouldShowTags(_ view: SearchView) -> Bool {
        return false
    }

    // MARK: - SubmitRequestCellDelegate

    func submitRequestCellTapped(_ cell: SubmitRequestCell) {
        self.searchView.show()
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return SECTION_COUNT
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case SECTION_EXPLANATION:
            return tableView.dequeueReusableCell(withIdentifier: "ExplanationCell")!
        case SECTION_REQUESTS:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PublicRequestCell") as! PublicRequestCell
            cell.request = self.requests[indexPath.row]
            return cell
        case SECTION_SUBMIT:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SubmitRequestCell") as! SubmitRequestCell
            cell.delegate = self
            return cell
        default:
            assertionFailure("invalid section \(indexPath.section)")
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case SECTION_EXPLANATION:
            return 1
        case SECTION_REQUESTS:
            return self.requests.count
        case SECTION_SUBMIT:
            return 0
        default:
            assertionFailure("invalid section \(section)")
            return 0
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case SECTION_EXPLANATION:
            return 100
        case SECTION_REQUESTS:
            return 90
        case SECTION_SUBMIT:
            return 72
        default:
            assertionFailure("invalid section \(indexPath.section)")
            return 0
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == SECTION_REQUESTS
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == SECTION_REQUESTS {
            let request = self.requests[indexPath.row]
            if request.reward != nil {
                let vc = self.storyboard!.instantiateViewController(withIdentifier: "PublicRequest") as! PublicRequestViewController
                vc.info = PublicContentRequestDetails(request: request)
                self.navigationController?.pushViewController(vc, animated: true)
            } else {
                TabBarController.showCreate(content: request.content, source: "Public Request Tapped")
            }
        }
        return nil
    }

    // MARK: - Actions

    @IBAction func helpTapped(_ sender: UIButton) {
        UIApplication.shared.open(SettingsManager.helpCoinsURL)
    }

    // MARK: - Private

    private let requestsTableRefresh = UIRefreshControl()

    private var cursor: String?
    private var isLoadingRequests = false
    private var searchView: SearchView!
    private var statusIndicatorView: StatusIndicatorView!

    private func loadRequests(firstPage: Bool = false, callback: ((Bool) -> ())? = nil) {
        guard firstPage || self.cursor != nil else {
            callback?(false)
            return
        }
        self.isLoadingRequests = true
        ContentService.instance.getPublicRequestList(tags: ["default"], cursor: firstPage ? nil : self.cursor) { list, cursor in
            self.isLoadingRequests = false
            // TODO: Error state.
            guard let list = list else {
                callback?(false)
                return
            }
            self.requests = list
            self.cursor = cursor
            callback?(true)
        }
    }

    @objc private dynamic func requestsTableRefreshPulled(_ sender: UIRefreshControl) {
        self.loadRequests(firstPage: true) { _ in
            sender.endRefreshing()
        }
    }

    private func submitRequest(ref: ContentRef) {
        self.statusIndicatorView.showLoading()
        let intent = Intent.createPublicContentRequest(relatedContent: ref, tags: ["default"])
        intent.perform(BackendClient.api) {
            guard $0.successful else {
                self.statusIndicatorView.hide()
                let alert = UIAlertController(
                    title: "Error!",
                    message: "Something went wrong. Try again.",
                    preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            self.statusIndicatorView.showConfirmation(title: "Submitted!")
        }
    }
}

class PublicRequestCell: UITableViewCell {
    @IBOutlet weak var rewardContainer: UIStackView!
    @IBOutlet weak var rewardLabel: UILabel!
    @IBOutlet weak var rewardCoinImage: UIImageView!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var thumbView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!

    var request: PublicContentRequest? {
        didSet {
            self.update()
        }
    }

    // MARK: - UITableViewCell

    override func prepareForReuse() {
        super.prepareForReuse()
        self.request = nil
        self.rewardContainer.isHidden = true
        self.thumbView.af_cancelImageRequest()
    }

    // MARK: - NSObject

    override func awakeFromNib() {
        super.awakeFromNib()
        let backgroundView = UIView()
        backgroundView.backgroundColor = .black
        self.backgroundView = backgroundView
        let highlightView = UIView()
        highlightView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        self.selectedBackgroundView = highlightView
        self.rewardLabel.setHeavyShadow()
        self.thumbView.layer.masksToBounds = true
        self.thumbView.layer.cornerRadius = 4
    }

    // MARK: - Private

    private func update() {
        guard let request = self.request else { return }
        if let url = request.content.thumbnailURL {
            self.thumbView.af_setImage(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
        } else {
            self.thumbView.af_cancelImageRequest()
            self.thumbView.image = #imageLiteral(resourceName: "relatedContent")
        }
        self.titleLabel.text = request.title
        self.subtitleLabel.text = request.subtitle
        if let reward = request.reward {
            if request.isClosed {
                self.rewardLabel.textColor = .white
                self.rewardLabel.text = "CLOSED"
                self.rewardCoinImage.isHidden = true
                self.thumbView.layer.borderColor = UIColor.white.cgColor
            } else {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                self.rewardLabel.text = formatter.string(from: NSNumber(value: reward))
                self.rewardLabel.textColor = .uiYellow
                self.rewardCoinImage.isHidden = false
                self.thumbView.layer.borderColor = UIColor.uiYellow.cgColor
            }
            self.rewardContainer.isHidden = false
            self.thumbView.layer.borderWidth = 1
        } else {
            self.rewardContainer.isHidden = true
            self.thumbView.layer.borderColor = UIColor(white: 1, alpha: 0.3).cgColor
            self.thumbView.layer.borderWidth = 0.5
        }
    }
}

class SubmitRequestCell: UITableViewCell {
    weak var delegate: SubmitRequestCellDelegate?

    @IBAction func submitRequestTapped(_ sender: HighlightButton) {
        self.delegate?.submitRequestCellTapped(self)
    }

    // MARK: - UITableViewCell

    override func prepareForReuse() {
        super.prepareForReuse()
    }

    // MARK: - NSObject

    override func awakeFromNib() {
        super.awakeFromNib()
    }
}

protocol SubmitRequestCellDelegate: class {
    func submitRequestCellTapped(_ cell: SubmitRequestCell)
}
