import UIKit
import WebKit

class InstagramLoginViewController: UIViewController, WKNavigationDelegate {
    
    @IBOutlet weak var loader: UIActivityIndicatorView!
    @IBOutlet weak var webViewContainer: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.loginWebView = WKWebView(frame: self.webViewContainer.bounds)
        self.loginWebView.navigationDelegate = self
        self.webViewContainer.addSubview(self.loginWebView)
        
        let authURL = String(format: "%@?client_id=%@&redirect_uri=%@&response_type=token&scope=%@&DEBUG=True", arguments: [
            InstagramInfo.authURL,
            InstagramInfo.clientId,
            InstagramInfo.redirectURI,
            InstagramInfo.scope
            ])
        let urlRequest =  URLRequest.init(url: URL.init(string: authURL)!)
        self.loginWebView.load(urlRequest)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.loginWebView.frame = self.webViewContainer.frame
    }
    
    func handleAuth(token: String)  {
        print("Instagram authentication token: ", token)
        SettingsManager.instagramOAuthToken = token
        self.dismiss(animated: true)
    }
    
    @IBAction func backTapped(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    // MARK: - WKWebViewDelegate
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.loader.startAnimating()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.loader.stopAnimating()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.loader.stopAnimating()
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let requestURLString = navigationAction.request.url?.absoluteString else {
            decisionHandler(.allow)
            return
        }
        if requestURLString.hasPrefix(InstagramInfo.redirectURI) {
            let range: Range<String.Index> = requestURLString.range(of: "#access_token=")!
            handleAuth(token: String(requestURLString[range.upperBound...]))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    
    private var loginWebView: WKWebView!

    private struct InstagramInfo {
        static let authURL = "https://api.instagram.com/oauth/authorize/"
        static let apiURL  = "https://api.instagram.com/v1/users/"
        static let accessToken = "access_token"
        static let scope = "follower_list+likes"

        static let clientId  = "_REMOVED_"
        static let clientSecret = "_REMOVED_"
        static let redirectURI = "https://www.reaction.cam/instagram/login/callback"
    }
}
