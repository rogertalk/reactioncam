import UIKit

class TagContentViewController: UIViewController {
    
    @IBOutlet weak var contentCollectionView: ContentCollectionView!
    @IBOutlet weak var emptyContentCTAView: UIView!
    @IBOutlet weak var titleLabel: UILabel!

    var contentTags = [String]() {
        didSet {
            guard !self.contentTags.isEmpty else {
                self.contentCollectionView.content = []
                return
            }
            var tags = self.contentTags
            tags.append("reaction")
            self.statusIndicatorView.showLoading()
            ContentService.instance.getContentList(tags: tags, sortBy: "hot") { result, _ in
                self.statusIndicatorView.hide()
                guard let content = result else {
                    let alert = UIAlertController(title: "Oops!", message: "Something went wrong. Please try again.", preferredStyle: .alert)
                    alert.addCancel(title: "OK") {
                        self.navigationController?.popViewController(animated: true)
                    }
                    self.present(alert, animated: true)
                    return
                }
                self.contentCollectionView.content = content
                self.emptyContentCTAView.isHidden = !content.isEmpty
            }
        }
    }
    
    var contentTitle: String? {
        didSet {
            guard let title = self.contentTitle else {
                let tags = self.contentTags.joined(separator: ", #")
                self.titleLabel.text = tags.isEmpty ? "Loading..." : "#\(tags)"
                return
            }
            self.titleLabel.text = self.contentTitle
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
    }
    
    @IBAction func backTapped(_ sender: Any) {
        self.navigationController?.popViewController(animated: true)
    }
    
    @IBAction func optionsTapped(_ sender: Any) {
    }
    
    @IBAction func createTapped(_ sender: Any) {
        TabBarController.showCreate(source: "Tag View Create Tapped")
    }
    
    private var statusIndicatorView: StatusIndicatorView!
}
