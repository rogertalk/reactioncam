import AVFoundation
import SwipeView
import MobileCoreServices
import OpenGraph
import UIKit
import XLActionController

enum SelectionMode { case react, request(account: Account?) }

fileprivate let SECTION_CLIPBOARD = 0
fileprivate let SECTION_CONTENT = 1
fileprivate let linkRegex = try! NSRegularExpression(pattern: "http[s]?://[^ ]*", options: [])

class PickSourceViewController: UIViewController,
    SearchViewDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout,
    UITextFieldDelegate
{
    var mode: SelectionMode = .react

    @IBOutlet weak var bannerView: UIView!
    @IBOutlet weak var contentSuggestionCollection: UICollectionView!
    @IBOutlet weak var keyboardHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var modeLabel: UILabel!
    @IBOutlet weak var moreButton: UIButton!
    @IBOutlet weak var searchField: SearchTextField!
    @IBOutlet weak var upsellCTAButton: HighlightButton!
    @IBOutlet weak var upsellView: UIView!

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.contentSuggestionCollection.register(UINib(nibName:"ContentGridCell", bundle: nil), forCellWithReuseIdentifier: "ContentGridCell")
        self.contentSuggestionCollection.register(UINib(nibName:"ContentSuggestionCell", bundle: nil), forCellWithReuseIdentifier: "ContentSuggestionCell")
        self.contentSuggestionCollection.dataSource = self
        self.contentSuggestionCollection.delegate = self
        self.contentSuggestionCollection.contentInset = UIEdgeInsets(top: 126, left: 0, bottom: 16, right: 0)
        self.contentSuggestionCollection.scrollIndicatorInsets = UIEdgeInsets(top: 126, left: 0, bottom: 0, right: 0)
        self.contentSuggestionCollection.keyboardDismissMode = .onDrag
        self.contentSuggestionCollection.indicatorStyle = .white

        self.imagePicker.delegate = self
        self.searchField.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(PickSourceViewController.keyboardEvent),
                                               name: .UIKeyboardWillChangeFrame, object: nil)

        self.bannerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(PickSourceViewController.bannerTapped)))

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.upsellView.isHidden = true
        self.upsellCTAButton.isHidden = UIApplication.shared.canOpenURL(URL(string: "igtv://")!)

        let searchView = Bundle.main.loadNibNamed("SearchView", owner: nil, options: nil)?.first as! SearchView
        searchView.delegate = self
        searchView.frame = self.view.bounds
        searchView.isHidden = true
        searchView.presenter = self
        self.view.addSubview(searchView)
        self.searchView = searchView

        //ContentService.instance.search(query: "") {
        //    self.contentSuggestions = $0
        //    self.contentSuggestionCollection.reloadData()
        //}

        NotificationCenter.default.addObserver(self, selector: #selector(PickSourceViewController.updateClipboard), name: .UIApplicationDidBecomeActive, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.updateClipboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.searchView.isHidden = true
        switch self.mode {
        case .react:
            self.modeLabel.text = "React"
            self.moreButton.isHidden = false
        case .request:
            self.modeLabel.text = "Request"
            self.moreButton.isHidden = true
        }
        self.searchField.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        self.view.endEditing(true)
    }

    @IBAction func closeTapped(_ sender: Any) {
        Logging.debug("Pick Source Action", ["Result": "Cancel"])
        self.dismiss(animated: true)
    }

    @IBAction func closeUpsellTapped(_ sender: Any) {
        Logging.debug("Pick Source Action", ["Result": "Close IGTV Upsell"])
        self.upsellView.hideAnimated()
        self.searchField.becomeFirstResponder()
    }

    @IBAction func moreTapped(_ sender: Any) {
        Logging.debug("Pick Source Action", ["Result": "More"])
        let sheet = ActionSheetController(title: "More…")
        sheet.addAction(Action("Request Reactions", style: .default) { _ in
            Logging.debug("Pick Source More Action", ["Result": "Request Reactions"])
            self.mode = .request(account: nil)
            self.moreButton.isHidden = true
            self.modeLabel.text = "Request"
            self.modeLabel.pulse()
        })
        sheet.addAction(Action("Record \(Date().weekDay) Vlog", style: .default) { _ in
            Logging.debug("Pick Source More Action", ["Result": "Vlog"])
            TabBarController.showCreate(source: "Pick Source View Record Vlog Option")
        })
        sheet.addAction(Action("Upload Video", style: .default) { _ in
            Logging.debug("Pick Source More Action", ["Result": "Upload"])
            self.imagePicker.sourceType = .photoLibrary
            self.imagePicker.mediaTypes = [kUTTypeMovie as String]
            self.present(self.imagePicker, animated: true)
        })
        sheet.addCancel() {
            Logging.debug("Pick Source More Action", ["Result": "Cancel"])
        }
        sheet.configurePopover(sourceView: self.moreButton)
        self.present(sheet, animated: true)
    }

    @IBAction func upsellCTATapped(_ sender: Any) {
        Logging.debug("Pick Source Action", ["Result": "IGTV Upsell Download"])
        let url = URL(string: "https://itunes.apple.com/us/app/igtv/id1394351700?mt=8")!
        UIApplication.shared.open(url)
    }

    // MARK: - SearchViewDelegate

    func searchView(_ view: SearchView, didSelect result: SearchView.Result) {
        let rawQuery = view.searchField.text ?? ""
        let query = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.hasPrefix("try not to") else {
            self.handle(searchResult: result)
            return
        }
        var otherResults = view.contentResults
        if case let .content(content, _) = result {
            otherResults = otherResults.filter { $0.id != content.id }
        }
        guard !otherResults.isEmpty else {
            self.handle(searchResult: result)
            return
        }
        let alert = UIAlertController(
            title: "Do you want to receive daily reaction requests like this?",
            message: query,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
            Logging.log("Pick Source Reaction Request Primer", ["Result": "Yes", "Input": query])
            self.handle(searchResult: result)
            // Schedule the first 7 other results (one per day).
            // TODO: Consider handling case where some schedules fail.
            var seconds = TimeInterval(23 * 60 * 60)
            for result in otherResults.prefix(7) {
                Intent.createOwnContentRequest(relatedContent: result.ref, delay: seconds).perform(BackendClient.api)
                seconds += 24 * 60 * 60
            }
        })
        alert.addCancel(title: "No") {
            Logging.log("Pick Source Reaction Request Primer", ["Result": "No", "Input": query])
            self.handle(searchResult: result)
        }
        self.present(alert, animated: true)
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

    // MARK: - UICollectionViewDataSource
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch indexPath.section {
        case SECTION_CLIPBOARD:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ContentSuggestionCell", for: indexPath) as! ContentSuggestionCell
            if let url = self.clipboardUrl {
                cell.titleLabel.text = url.absoluteString
                //cell.titleLabel.textColor = .uiYellow
                OpenGraph.fetch(url: url) { og, error in
                    if let title = og?[.title]?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !title.isEmpty {
                        DispatchQueue.main.async {
                            cell.titleLabel.text = title
                        }
                    }
                    if let urlString = og?[.image], let thumbURL = URL(string: urlString) {
                        DispatchQueue.main.async {
                            cell.thumbnailImageView.af_setImageBiased(withURL: thumbURL, placeholderImage: #imageLiteral(resourceName: "shareLink"))
                        }
                    }
                }
            } else {
                cell.titleLabel.text = "Copy a link from any app"
                cell.thumbnailImageView.af_cancelImageRequest()
                cell.thumbnailImageView.image = #imageLiteral(resourceName: "shareLink")
            }
            return cell
        case SECTION_CONTENT:
            // create a new cell if needed or reuse an old one
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ContentGridCell", for: indexPath) as! ContentGridCell
            let suggestion = self.contentSuggestions[indexPath.row]
            if let url = suggestion.thumbnailURL {
                cell.thumbnailImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "relatedContent"))
            } else {
                cell.thumbnailImageView.af_cancelImageRequest()
                cell.thumbnailImageView.image = #imageLiteral(resourceName: "relatedContent")
            }
            cell.titleLabel.text = suggestion.title
            return cell
        default:
            return UICollectionViewCell()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch indexPath.section {
        case SECTION_CLIPBOARD:
            guard let url = self.clipboardUrl else {
                Logging.debug("Pick Source Action", ["Result": "Clipboard Link Placeholder"])
                let alert = UIAlertController(title: "React to Link 🔗", message: "React to ANYTHING on the internet. Copy a link from any app and pick it here to react!", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            Logging.debug("Pick Source Action", ["Result": "Clipboard Link"])
            self.present(url: url, source: "Pick Source View Clipboard Link")
        case SECTION_CONTENT:
            guard let url = self.contentSuggestions[indexPath.row].originalURL else {
                Logging.debug("Pick Source Action", ["Result": "Content Suggestion Error"])
                return
            }
            Logging.debug("Pick Source Action", ["Result": "Content Suggestion"])
            self.present(url: url, source: "Pick Source View Content Suggestion")
        default:
            break
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case SECTION_CLIPBOARD:
            return 1
        case SECTION_CONTENT:
            return self.contentSuggestions.count
        default:
            return 0
        }
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        switch indexPath.section {
        case SECTION_CLIPBOARD:
            return CGSize(width: collectionView.bounds.width, height: 50)
        case SECTION_CONTENT:
            let width = (collectionView.bounds.width - 32) / 2 - 4
            return CGSize(width: width, height: width * 9 / 16 + 72)
        default:
            return .zero
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 8
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionElementKindSectionHeader, withReuseIdentifier: "SuggestionCollectionHeaderView", for: indexPath) as! SuggestionCollectionHeaderView
        switch indexPath.section {
        case SECTION_CLIPBOARD:
            header.dateLabel.isHidden = true
            header.titleLabel.text = "Clipboard"
        case SECTION_CONTENT:
            header.dateLabel.text = Date().dateLabel.uppercased()
            header.dateLabel.isHidden = false
            header.titleLabel.text = "Trending Today"
        default:
            break
        }
        return header
    }
    
    // MARK: - UIImagePickerViewControllerDelegate

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        Logging.debug("Pick Source Action", ["Result": "Upload (Cancel)"])
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String: Any]) {
        guard let movieURL = info[UIImagePickerControllerMediaURL] as? URL else {
            Logging.debug("Pick Source Action", ["Result": "MissingMedia"])
            picker.dismiss(animated: true)
            return
        }
        picker.dismiss(animated: true)
        self.view.isUserInteractionEnabled = false
        self.statusIndicatorView.showLoading(title: "Importing...")
        let asset = AVURLAsset(url: movieURL)
        AssetEditor.sanitize(asset: asset) {
            self.view.isUserInteractionEnabled = true
            self.statusIndicatorView.hide()
            guard let result = $0 else {
                Logging.log("Pick Source Action", ["Result": "Upload", "Success": false])
                let alert = UIAlertController(title: "Oops!", message: "Something went wrong. Please try again.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            Logging.log("Pick Source Action", ["Result": "Upload", "Success": true])
            let content = PendingContent(assets: [result])
            content.type = .upload
            TabBarController.instance?.showReview(content: content, source: "Upload (Pick Source)")
        }
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        self.searchView.show(searchString: string != "\n" ? string : nil)
        return false
    }

    // MARK: - Private

    private var clipboardUrl: URL?
    private var contentSuggestions = [ContentResult]()
    private var searchView: SearchView!

    private let imagePicker = UIImagePickerController()
    private var statusIndicatorView: StatusIndicatorView!

    private struct Section {
        static let clipboard = 0
        static let undiscovered = 1
    }

    @objc private dynamic func bannerTapped() {
        Logging.debug("Pick Source Action", ["Result": "IGTV Banner Tapped"])
        self.searchField.resignFirstResponder()
        self.upsellView.showAnimated()
    }

    private func handle(searchResult result: SearchView.Result) {
        var url: URL?
        var ref: ContentRef?
        let resultSource: String
        switch result {
        case let .content(content, source):
            url = content.originalURL
            ref = content.ref
            resultSource = source
        case let .googleQuery(query):
            url = query.searchURL()
            resultSource = "Google Search"
        default:
            assertionFailure("Unexpected result picked: \(result)")
            resultSource = "Unknown"
        }
        switch self.mode {
        case .react:
            TabBarController.showCreate(url: url, ref: ref, relevantUsername: nil,
                                        source: "Pick Source (React) \(resultSource)")
        case let .request(account: account):
            TabBarController.showCreate(url: url, ref: ref, requesting: account,
                                        source: "Pick Source (Request) \(resultSource)")
        }
    }

    @objc private dynamic func keyboardEvent(notification: NSNotification) {
        self.view.layoutIfNeeded()
        let frame = notification.userInfo![UIKeyboardFrameEndUserInfoKey] as! CGRect
        self.keyboardHeightConstraint.constant = self.view.frame.height - frame.minY
        self.view.layoutIfNeeded()
        UIView.commitAnimations()
    }

    private func present(url: URL, source: String) {
        switch self.mode {
        case .react:
            TabBarController.showCreate(url: url, ref: nil, relevantUsername: nil, source: source)
        case let .request(account):
            TabBarController.showCreate(url: url, requesting: account, source: source)
        }
    }

    @objc private dynamic func updateClipboard() {
        guard
            let text = UIPasteboard.general.string as NSString?,
            let match = linkRegex.matches(in: text as String, options: [], range: NSMakeRange(0, text.length)).first,
            let url = URL(string: text.substring(with: match.range)),
            !["rcam.at", "reaction.cam", "www.reaction.cam"].contains(url.host ?? ""),
            self.clipboardUrl != url else {
            return
        }
        self.clipboardUrl = url
        self.contentSuggestionCollection.reloadData()
    }
}

class ContentSuggestionCell: UICollectionViewCell {
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!

    var thumbURL: String? {
        didSet {
            if let urlString = self.thumbURL, let url = URL(string: urlString) {
                self.thumbnailImageView.af_setImageBiased(withURL: url, placeholderImage: #imageLiteral(resourceName: "shareLink"))
            } else {
                self.thumbnailImageView.af_cancelImageRequest()
                self.thumbnailImageView.image = #imageLiteral(resourceName: "shareLink")
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        //self.titleLabel.textColor = .white
        self.titleLabel.text = ""
        self.thumbURL = nil
    }
}

class SuggestionCollectionHeaderView: UICollectionReusableView {
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
}
