import UIKit

protocol OriginalPickerDelegate {
    func originalPicker(_ picker: OriginalPickerViewController, didFinishPicking content: ContentRef)
}

class OriginalPickerViewController : UIViewController, PresentationViewDelegate {
    
    var delegate: OriginalPickerDelegate?
    
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var contentContainer: UIView!
    @IBOutlet weak var confirmButton: HighlightButton!
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.contentContainer.insertSubview(self.videoView, at: 0)
        self.contentContainer.insertSubview(self.presentationView, at: 0)
        self.presentationView.attachment = .webPage(URL(string: "https://google.com")!)
        self.presentationView.delegate = self
        self.videoView.isHidden = true
        self.videoView.backgroundColor = .black
        self.videoView.orientation = .portrait
        
        self.loadDidRun = true
        if let url = self.pendingPresentationURL {
            self.pendingPresentationURL = nil
            self.present(url: url)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.presentationView.frame = self.contentContainer.bounds
        self.videoView.frame = self.contentContainer.bounds
    }
    
    func present(url: URL) {
        guard self.loadDidRun else {
            self.pendingPresentationURL = url
            return
        }
        self.presentationView.attachment = .webPage(url)
    }
    
    // MARK: - Actions
    
    @IBAction func backTapped(_ sender: Any) {
        if !self.videoView.isHidden {
            self.videoView.hideAnimated()
            self.confirmButton.isHidden = true
            self.backButton.setTitle("keyboard_arrow_down", for: .normal)
            self.videoView.clearVideo()
        } else {
            self.dismiss(animated: true)
        }
    }
    
    @IBAction func confirmTapped(_ sender: Any) {
        guard let info = self.pageInfo, let ref = self.makeContentRef(from: info) else {
            self.dismiss(animated: true)
            return
        }
        self.delegate?.originalPicker(self, didFinishPicking: ref)
    }

    // MARK: - PresentationViewDelegate
    
    func presentationView(_ view: PresentationView, didChangeTitle title: String) {
        guard let oldInfo = self.pageInfo else {
            return
        }
        self.pageInfo = PageInfo(
            frame: oldInfo.frame,
            pageThumbURL: oldInfo.pageThumbURL,
            pageTitle: title,
            pageURL: oldInfo.pageURL,
            mediaId: oldInfo.mediaId,
            mediaURL: oldInfo.mediaURL)
    }
    
    func presentationView(_ view: PresentationView, didLoadContent info: PageInfo) {
        self.pageInfo = info
    }
    
    func presentationView(_ view: PresentationView, requestingToPlay mediaURL: URL, with info: PageInfo) {
        self.pageInfo = info
        self.videoView.showAnimated()
        self.confirmButton.isHidden = false
        self.backButton.setTitle("close", for: .normal)
        self.videoView.loadVideo(url: mediaURL)
        self.videoView.showUI()
    }
    
    func presentationViewRequestingToRecord(_ view: PresentationView) { }
    
    func presentationView(_ view: PresentationView, willLoadContent info: PageInfo) {
        self.pageInfo = info
    }
    
    // MARK: - Private

    private var loadDidRun = false
    private var pageInfo: PageInfo?
    private var pendingPresentationURL: URL?

    private let presentationView = PresentationView(frame: .zero)
    private let videoView = VideoView(frame: .zero, shouldProvideTexture: true)
    
    private func makeContentRef(from pageInfo: PageInfo) -> ContentRef? {
        let title = pageInfo.cleanTitle
        guard !title.isEmpty, var url = pageInfo.pageURL else {
            return nil
        }
        if let path = Bundle.main.resourcePath, url.path.hasPrefix(path) {
            url = URL(fileURLWithPath: "/ReactionCam.app" + url.path.dropFirst(path.count),
                      isDirectory: url.hasDirectoryPath)
        }
        return .metadata(
            creator: "TODO",
            url: url,
            duration: Int((self.videoView.videoDuration ?? 0) * 1000),
            title: title,
            videoURL: pageInfo.mediaURL,
            thumbURL: nil)
    }
}
