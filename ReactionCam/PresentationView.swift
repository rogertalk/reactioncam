import UIKit
import WebKit

fileprivate let ignoredSuffixes = [
    " - YouTube",
    " - Google Search",
]

struct PageInfo {
    let frame: CGRect

    let pageThumbURL: URL?
    let pageTitle: String?
    let pageURL: URL?

    let mediaId: String?
    let mediaURL: URL?

    var cleanTitle: String {
        guard let title = self.pageTitle else {
            return self.pageURL?.host ?? ""
        }
        // If any suffix matches, remove it and return the result.
        for suffix in ignoredSuffixes {
            if title.hasSuffix(suffix) {
                return String(title.dropLast(suffix.count))
            }
        }
        return title
    }
}

protocol PresentationViewDelegate: class {
    func presentationView(_ view: PresentationView, didChangeTitle title: String)
    func presentationView(_ view: PresentationView, didLoadContent info: PageInfo)
    func presentationView(_ view: PresentationView, requestingToPlay mediaURL: URL, with info: PageInfo)
    func presentationViewRequestingToRecord(_ view: PresentationView)
    func presentationView(_ view: PresentationView, willLoadContent info: PageInfo)
}

class PresentationView: UIView, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    // TODO: Use different enum or files vs webpages if we decide on different UX
    enum Attachment {
        case none
        case document(URL)
        case image(UIImage)
        case webPage(URL)
    }

    var attachment: Attachment = .none {
        didSet {
            self.activityIndicator.stopAnimating()
            switch oldValue {
            case .none:
                break
            case .document, .webPage:
                guard let webView = self.webView else {
                    break
                }
                webView.removeFromSuperview()
                self.webView = nil
            case .image:
                self.imageView.isHidden = true
                self.imageView.zoomView?.removeFromSuperview()
            }
            switch self.attachment {
            case let .document(url):
                let webView = self.createWebView()
                webView.loadFileURL(url, allowingReadAccessTo: url)
                self.webView = webView
                self.addSubview(webView)
            case let .image(image):
                self.imageView.isHidden = false
                self.imageView.display(image: image)
            case let .webPage(url):
                let webView = self.createWebView()
                webView.load(URLRequest(url: url))
                self.webView = webView
                self.addSubview(webView)
                self.bringSubview(toFront: self.activityIndicator)
                self.activityIndicator.startAnimating()
            case .none:
                break
            }
        }
    }

    var canGoBack: Bool {
        return self.webView?.canGoBack ?? false
    }

    weak var delegate: PresentationViewDelegate?

    var hasAttachment: Bool {
        if case .none = self.attachment {
            return false
        }
        return true
    }

    func goBack() {
        self.webView?.goBack()
    }

    func notifyMediaScript(id: String, type: String) {
        // TODO: Ensure these strings don't break.
        let js = "window.__abFlNG8d4k6PlMHewiCh__.event(`\(id)`, `\(type)`);"
        self.webView?.evaluateJavaScript(js)
    }

    // MARK: - UIView

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .black

        self.activityIndicator.center = CGPoint(x: self.frame.midX, y: self.frame.midY)
        self.activityIndicator.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin, .flexibleBottomMargin, .flexibleLeftMargin]
        self.activityIndicator.hidesWhenStopped = true
        self.addSubview(self.activityIndicator)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let webView = self.webView else {
            return
        }
        if self.window == nil {
            self.unhookJS(for: webView)
            self.webViewHooked = false
        } else if !self.webViewHooked {
            self.hookJS(for: webView)
            self.webViewHooked = true
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.webView?.frame = self.bounds
        self.imageView.frame = self.bounds
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // TODO: This breaks some JavaScript apps, consider fixing.
        if navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
            webView.load(navigationAction.request)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let errStr = error.localizedDescription
        let urlStr = webView.url?.absoluteString ?? "N/A"
        let webViewLog = "Error\t\(errStr)\t\(urlStr)"
        if webViewLog != self.lastWebViewLog {
            Logging.warning("Web View Error", ["Error": errStr, "URL": urlStr])
            self.lastWebViewLog = webViewLog
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let errStr = error.localizedDescription
        let urlStr = webView.url?.absoluteString ?? "N/A"
        let webViewLog = "Error\t\(errStr)\t\(urlStr)"
        if webViewLog != self.lastWebViewLog {
            Logging.warning("Web View Error", ["Error": errStr, "URL": urlStr])
            self.lastWebViewLog = webViewLog
        }
        let steveURL = URL(fileURLWithPath: Bundle.main.resourcePath!.appending("/steve"), isDirectory: true)
        let indexURL = steveURL.appendingPathComponent("index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: steveURL)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let urlStr = webView.url?.absoluteString ?? "N/A"
        let webViewLog = "Loading\t\(urlStr)"
        if webViewLog != self.lastWebViewLog {
            Logging.debug("Web View", ["State": "Loading", "URL": urlStr])
            self.lastWebViewLog = webViewLog
        }
        let info = PageInfo(frame: webView.bounds,
                            pageThumbURL: nil,
                            pageTitle: webView.title,
                            pageURL: webView.url,
                            mediaId: nil, mediaURL: nil)
        self.lastReportedThumbURL = nil
        self.lastReportedTitle = info.pageTitle
        self.delegate?.presentationView(self, willLoadContent: info)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            let webView = message.webView,
            let info = message.body as? [String: Any],
            let type = info["type"] as? String
            else { return }
        switch type {
        case "error":
            Logging.danger("Web View Script Error", [
                "Context": info["context"] as? String ?? "N/A",
                "Error": info["error"] as? String ?? "N/A"])
        case "load":
            let urlStr = webView.url?.absoluteString ?? "N/A"
            let webViewLog = "Loaded\t\(urlStr)"
            if webViewLog != self.lastWebViewLog {
                Logging.debug("Web View", ["State": "Loaded", "URL": urlStr])
                self.lastWebViewLog = webViewLog
            }
            self.activityIndicator.stopAnimating()
            let info = PageInfo(frame: webView.bounds,
                                pageThumbURL: (info["image"] as? String).flatMap(URL.init(string:)),
                                pageTitle: (info["title"] as? String) ?? webView.title,
                                pageURL: webView.url,
                                mediaId: nil,
                                mediaURL: nil)
            self.lastReportedThumbURL = info.pageThumbURL
            self.lastReportedTitle = info.pageTitle
            self.delegate?.presentationView(self, didLoadContent: info)
        case "play":
            guard
                let id = info["id"] as? String,
                let src = info["src"] as? String,
                let url = URL(string: src),
                let rect = info["frame"] as? [String: CGFloat],
                let x = rect["x"], let y = rect["y"],
                let width = rect["width"], let height = rect["height"]
                else { return }
            let frame = CGRect(x: x, y: y, width: width, height: height)
            let scroll = webView.scrollView.contentOffset
            let info = PageInfo(frame: frame.offsetBy(dx: scroll.x, dy: scroll.y),
                                pageThumbURL: self.lastReportedThumbURL,
                                pageTitle: (info["title"] as? String) ?? webView.title,
                                pageURL: message.webView?.url,
                                mediaId: id,
                                mediaURL: url)
            self.lastReportedTitle = info.pageTitle
            self.delegate?.presentationView(self, requestingToPlay: url, with: info)
        case "record":
            self.delegate?.presentationViewRequestingToRecord(self)
        case "title":
            guard
                let title = info["title"] as? String,
                title != self.lastReportedTitle
                else { break }
            self.lastReportedTitle = title
            self.delegate?.presentationView(self, didChangeTitle: title)
        default:
            print("Unhandled message type \(type)")
        }
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame?.isMainFrame != true {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - Private

    private static let hijackJS = try! String(contentsOfFile: Bundle.main.path(forResource: "HijackVideo", ofType: "js")!)

    private let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
    private let panGesture = UIPanGestureRecognizer()
    private let path = UIBezierPath()
    private let tapGesture = UITapGestureRecognizer()

    private var lastWebViewLog: String?

    private var webView: WKWebView? {
        didSet {
            if let webView = oldValue {
                self.unhookJS(for: webView)
            }
            if let webView = self.webView {
                self.hookJS(for: webView)
                self.webViewHooked = true
            } else {
                self.webViewHooked = false
            }
        }
    }

    private var lastReportedThumbURL: URL?
    private var lastReportedTitle: String?
    private var webViewHooked = false

    private lazy var imageView: ImageScrollView! = {
        let view = ImageScrollView(frame: self.bounds)
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        self.addSubview(view)
        return view
    }()

    private func createWebView() -> WKWebView {
        // Load a script that will hijack audio/video.
        let script = WKUserScript(source: PresentationView.hijackJS,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        // Create a controller which will receive messages from the hijack script.
        let controller = WKUserContentController()
        controller.addUserScript(script)
        // Create and configure a web view used for presentations.
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let view = WKWebView(frame: self.bounds, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.allowsLinkPreview = false
        view.navigationDelegate = self
        view.uiDelegate = self
        return view
    }

    private func hookJS(for webView: WKWebView) {
        webView.configuration.userContentController.add(self, name: "reactionCam")
    }

    private func unhookJS(for webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "reactionCam")
    }
}
