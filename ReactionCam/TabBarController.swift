import Alamofire
import AlamofireImage
import AVFoundation
import FBSDKCoreKit
import MobileCoreServices
import XLActionController
import UIKit

class TabBarController: UITabBarController,
    UITabBarControllerDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate
{

    var isHidden: Bool = false {
        didSet {
            self.tabBar.isHidden = self.isHidden
            self.creationButton.isHidden = self.isHidden
        }
    }

    static var instance: TabBarController?

    static func showCreate(content: ContentResult, relevantUsername: String? = nil, source: String) {
        TabBarController.showCreate(url: content.originalURL, ref: content.ref,
                                    relevantUsername: relevantUsername,
                                    source: source)
    }

    static func showCreate(content: ContentInfo, relevantUsername: String? = nil, source: String) {
        let url: URL?
        if let originalURL = content.originalURL, originalURL.host != "www.reaction.cam" {
            url = originalURL
        } else {
            url = content.videoURL
        }
        TabBarController.showCreate(
            url: url,
            ref: content.ref,
            relevantUsername: relevantUsername,
            source: source)
    }

    static func showCreate(request: PublicContentRequest, source: String) {
        TabBarController.showCreate(
            url: request.content.originalURL,
            ref: request.content.ref,
            request: request,
            source: source)
    }

    static func showCreate(url: URL? = nil, ref: ContentRef? = nil, relevantUsername: String? = nil, request: PublicContentRequest? = nil, source: String) {
        guard let bar = TabBarController.instance else {
            TabBarController.pendingCall = {
                TabBarController.showCreate(
                    url: url,
                    ref: ref,
                    relevantUsername: relevantUsername,
                    request: request,
                    source: source)
            }
            return
        }
        let creation = bar.newCreation(source: source)
        if let url = url {
            creation.present(url: url, ref: ref)
        }
        creation.requesterUsername = relevantUsername
        creation.content.request = request
        bar.navigationController?.pushViewControllerModal(creation)
        bar.presentedViewController?.dismiss(animated: true)
    }

    static func showCreate(url: URL?, ref: ContentRef? = nil, requesting account: Account?, source: String) {
        guard let bar = TabBarController.instance else {
            TabBarController.pendingCall = {
                TabBarController.showCreate(
                    url: url,
                    ref: ref,
                    requesting: account,
                    source: source)
            }
            return
        }
        let creation = bar.newCreation(source: source)
        if let url = url {
            creation.present(url: url, ref: ref)
        }
        creation.mode = .request(account: account)
        bar.navigationController?.pushViewControllerModal(creation)
        bar.presentedViewController?.dismiss(animated: true)
    }

    static func select(account: Account, showChat: Bool = false) {
        guard let bar = TabBarController.instance, let navigation = bar.navigationController else {
            TabBarController.pendingCall = { TabBarController.select(account: account, showChat: showChat) }
            return
        }
        bar.presentedViewController?.dismiss(animated: true)
        if let profile = navigation.secondFromTopViewController as? ProfileViewController,
            profile.account?.id == account.id {
            profile.startInChat = showChat
            navigation.popViewController(animated: true)
        } else if let profile = loadVC(ProfileViewController.self) {
            profile.account = account
            profile.startInChat = showChat
            navigation.pushViewController(profile, animated: true)
        }
    }

    static func select(content: Content, offset: Double? = nil) {
        guard let bar = TabBarController.instance else {
            TabBarController.pendingCall = { TabBarController.select(content: content, offset: offset) }
            return
        }
        bar.presentedViewController?.dismiss(animated: true)
        let vc = bar.storyboard!.instantiateViewController(withIdentifier: "Content") as! ContentViewController
        vc.contentOffset = offset
        vc.recentContent = [content]
        vc.presetContentId = content.id
        bar.navigationController!.pushViewController(vc, animated: true)
    }

    static func select(contentId: Int64, offset: Double? = nil, action: ContentViewController.ContentAction? = nil) {
        guard let bar = TabBarController.instance else {
            TabBarController.pendingCall = { TabBarController.select(contentId: contentId, offset: offset, action: action) }
            return
        }
        bar.presentedViewController?.dismiss(animated: true)
        let vc = bar.storyboard!.instantiateViewController(withIdentifier: "Content") as! ContentViewController
        vc.contentOffset = offset
        vc.presetContentId = contentId
        vc.action = action
        bar.navigationController!.pushViewController(vc, animated: true)
    }

    static func select(contentList: [Content], presetContentId: Int64) {
        guard let bar = TabBarController.instance else {
            TabBarController.pendingCall = { TabBarController.select(contentList: contentList, presetContentId: presetContentId) }
            return
        }
        let vc = bar.storyboard!.instantiateViewController(withIdentifier: "Content") as! ContentViewController
        vc.recentContent = contentList
        vc.presetContentId = presetContentId
        bar.navigationController!.pushViewController(vc, animated: true)
    }

    static func select(originalContent content: ContentResult, source: String) {
        ContentService.instance.getContent(id: content.id) {
            guard let content = $0 else {
                return
            }
            TabBarController.select(originalContent: content, source: source)
        }
    }

    static func select(originalContent content: ContentInfo, inject injectedContent: Content? = nil, tab: OriginalContentViewController.Tab = .top, suggestSimilarCreators: Bool = false, animated: Bool = true, source: String) {
        guard let bar = TabBarController.instance, let navigation = bar.navigationController else {
            TabBarController.pendingCall = { TabBarController.select(originalContent: content, inject: injectedContent, tab: tab, animated: animated, source: source) }
            return
        }
        bar.presentedViewController?.dismiss(animated: true)

        if let original = navigation.secondFromTopViewController as? OriginalContentViewController,
            original.content.id == content.id {
            original.injectedContent = injectedContent
            original.preselectedTab = tab
            original.source = source
            original.suggestSimilarCreators = suggestSimilarCreators
            navigation.popViewController(animated: true)
        } else {
            let vc = bar.storyboard!.instantiateViewController(withIdentifier: "OriginalContent") as! OriginalContentViewController
            vc.content = content
            vc.injectedContent = injectedContent
            vc.preselectedTab = tab
            vc.source = source
            vc.suggestSimilarCreators = suggestSimilarCreators
            navigation.pushViewController(vc, animated: animated)
        }
    }

    static func select(request: PublicContentRequest, source: String) {
        guard let bar = TabBarController.instance, let navigation = bar.navigationController else {
            TabBarController.pendingCall = { TabBarController.select(request: request, source: source) }
            return
        }
        let vc = bar.storyboard!.instantiateViewController(withIdentifier: "PublicRequest") as! PublicRequestViewController
        vc.info = PublicContentRequestDetails(request: request)
        navigation.pushViewController(vc, animated: true)
    }

    static func select(tab: Tab, source: String) {
        guard let bar = TabBarController.instance else {
            TabBarController.pendingCall = { TabBarController.select(tab: tab, source: source) }
            return
        }
        guard tab != .create else {
            bar.showCreationPicker(source: source)
            return
        }
        bar.selectedIndex = tab.rawValue
        if let nav = bar.navigationController, nav.topViewController != bar {
            nav.popToRootViewControllerModal()
        }
    }

    static func select(tags: [String], title: String? = nil) {
        guard let bar = TabBarController.instance, let navigation = bar.navigationController else {
                TabBarController.pendingCall = { TabBarController.select(tags: tags, title: title) }
                return
        }
        // Go back one page if the next is same as previous
        if let contentTags = (navigation.secondFromTopViewController as? TagContentViewController)?.contentTags, contentTags == tags {
            navigation.popViewController(animated: true)
        } else {
            guard let vc = loadVC(TagContentViewController.self) else {
                return
            }
            vc.contentTags = tags
            vc.contentTitle = title
            navigation.pushViewController(vc, animated: true)
        }
    }

    static func select(thread: MessageThread) {
        guard let bar = TabBarController.instance, let messages = loadVC(MessagesViewController.self) else {
            TabBarController.pendingCall = { TabBarController.select(thread: thread) }
            return
        }
        messages.thread = thread
        bar.presentedViewController?.dismiss(animated: true)
        bar.navigationController?.pushViewController(messages, animated: true)
    }

    static func showQuiz() {
        guard let bar = TabBarController.instance, let quiz = loadVC(QuizViewController.self) else {
            TabBarController.pendingCall = { TabBarController.showQuiz() }
            return
        }
        bar.present(quiz, animated: true)
    }

    static func showRewards(for account: Account) {
        guard
            let nav = TabBarController.instance?.navigationController,
            let rewards = loadVC(RewardsViewController.self)
            else
        {
            TabBarController.pendingCall = { TabBarController.showRewards(for: account) }
            return
        }
        rewards.modalPresentationStyle = .overCurrentContext
        rewards.modalTransitionStyle = .crossDissolve
        if let account = account as? AccountWithExtras {
            rewards.account = account
            nav.present(rewards, animated: true)
        } else {
            Intent.getProfile(identifier: String(account.id)).perform(BackendClient.api) {
                guard $0.successful, let data = $0.data else {
                    return
                }
                rewards.account = Profile(data: data)
                nav.present(rewards, animated: true)
            }
        }
    }

    static func updateBadgeNumber() {
        let count = NotificationService.instance.unseenCount + MessageService.instance.unseenCount
        UIApplication.shared.applicationIconBadgeNumber = count

        guard let item = TabBarController.instance?.tabBar.items?[Tab.notifications.rawValue] else {
            return
        }
        if count > 0 {
            item.badgeColor = .red
            item.badgeValue = String(count)
        } else {
            item.badgeValue = nil
        }
    }

    enum Tab: Int {
        case requests
        case search
        case create
        case notifications
        case profile
    }

    var tooltip: TooltipView!

    func showAskShare() {
        guard let askShare = Bundle.main.loadNibNamed("AskShareViewController", owner: nil, options: nil)?.first as? AskShareViewController else {
            return
        }
        askShare.modalPresentationStyle = .overCurrentContext
        askShare.modalTransitionStyle = .crossDissolve
        self.present(askShare, animated: true)
    }
    
    func showCreationPicker(source: String, mode: SelectionMode = .react) {
        Logging.log("Pick Source Shown", ["Source": source])
        let pickSource = self.storyboard?.instantiateViewController(withIdentifier: "PickSource") as! PickSourceViewController
        pickSource.mode = mode
        self.present(pickSource, animated: true)
    }

    func showRate(source: String) {
        Logging.log("Show Rate", ["Source": source])
        guard let rate = loadVC(AskRateViewController.self) else {
            return
        }
        // Disable all rating UI across app for a bit
        SettingsManager.didAskToRate = true

        rate.modalPresentationStyle = .overCurrentContext
        rate.modalTransitionStyle = .crossDissolve
        self.present(rate, animated: true)
    }

    func showReview(content: PendingContent, source: String) {
        let review = self.storyboard?.instantiateViewController(withIdentifier: "Review") as! ReviewViewController
        review.content = content
        review.source = source
        self.navigationController?.pushViewControllerModal(review)
        self.presentedViewController?.dismiss(animated: true)
    }

    // MARK: - UIViewController

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        guard let session = BackendClient.api.session else {
            return
        }
        // If this is after onboarding, there may be deep linked content to handle.
        guard !AppDelegate.handlePendingDeepLink() else {
            return
        }
        if let call = TabBarController.pendingCall {
            // An action was requested while the app was still starting up.
            TabBarController.pendingCall = nil
            DispatchQueue.main.async {
                call()
            }
        } else if !SetDemoViewController.shouldAskLater && (session.birthday == nil || session.gender == nil) {
            // The user hasn't set up their demographics yet.
            let vc = self.storyboard?.instantiateViewController(withIdentifier: "SetDemo")
            self.present(vc!, animated: true)
        } else if !SettingsManager.didSuggestFriends {
            self.checkFacebookFriends() {
                guard $0, let vc = loadVC(SuggestedUsersViewController.self) else {
                    return
                }
                SettingsManager.didSuggestFriends = true
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let items = self.tabBar.items, let view = items[items.count / 2].value(forKey: "view") as? UIView {
            let o = self.tabBar.frame.origin, d = view.center
            self.creationButton.center = CGPoint(x: o.x + d.x, y: o.y + d.y)
        } else {
            self.creationButton.center = self.tabBar.center
        }
        self.tooltip.setNeedsLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        TabBarController.instance = self

        self.tabBar.layer.borderWidth = 0
        self.tabBar.clipsToBounds = true

        self.delegate = self
        self.imagePicker.delegate = self

        let itemWidth = self.tabBar.frame.width / 5
        self.tabBar.itemPositioning = .automatic
        self.tabBar.unselectedItemTintColor = UIColor.white.withAlphaComponent(0.4)
        self.tabBar.shadowImage = nil
        self.tabBar.backgroundImage = UIImage()

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        let creationButton = UIButton()
        creationButton.titleLabel?.font = .materialFont(ofSize: 40)
        creationButton.setTitle("add_box", for: .normal)
        creationButton.setTitleColor(.uiYellow, for: .normal)
        let height = self.tabBar.frame.height
        creationButton.frame.size = CGSize(width: itemWidth, height: height)
        creationButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(TabBarController.creationButtonTapped)))
        creationButton.center = self.tabBar.center
        self.view.addSubview(creationButton)
        self.creationButton = creationButton

        self.tooltip = TooltipView(text: "Tap + to start!", centerView: creationButton)
        self.view.addSubview(self.tooltip)

        let profile = loadVC(ProfileViewController.self)!
        let barItem = UITabBarItem(title: nil, image: #imageLiteral(resourceName: "person"), selectedImage: nil)
        barItem.imageInsets = UIEdgeInsets(top: 5.5, left: 0, bottom: -5.5, right: 0)
        profile.tabBarItem = barItem
        self.viewControllers?.append(profile)

        let session = BackendClient.api.session
        // Show badge if user has not logged in.
        if session?.hasBeenOnboarded == false, let item = self.tabBar.items?[Tab.profile.rawValue] {
            item.badgeColor = .red
            item.badgeValue = "!"
            BackendClient.api.sessionChanged.addListener(self, method: TabBarController.handleSessionChanged)
        }

        TabBarController.updateBadgeNumber()

        self.networkAlert.addAction(UIAlertAction(title: "Settings", style: .default) { (_) in
            UIApplication.shared.open(URL(string:UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: { (_) in
            })
        })
        self.networkAlert.addAction(UIAlertAction(title: "OK", style: .default) { _ in })
        // Monitor for changes to network status.
        self.networkManager?.listener = { _ in
            self.updateNetworkAlert()
        }
        self.networkManager?.startListening()
        self.updateNetworkAlert()
        
        self.updateProfileImage()
        BackendClient.api.sessionChanged.addListener(self, method: TabBarController.updateProfileImage)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    // MARK: - UIImagePickerViewControllerDelegate

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        Logging.debug("Create Action", ["Result": "Upload (Cancel)"])
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String: Any]) {
        guard let movieURL = info[UIImagePickerControllerMediaURL] as? URL else {
            Logging.log("Create Action", ["Result": "Camera Roll (Cancel)"])
            picker.dismiss(animated: true)
            return
        }
        picker.dismiss(animated: true)
        self.view.isUserInteractionEnabled = false
        self.statusIndicatorView.showLoading(title: "Importing...")
        let asset = AVURLAsset(url: movieURL)
        AssetEditor.sanitize(asset: asset) { result in
            self.view.isUserInteractionEnabled = true
            self.statusIndicatorView.hide()
            guard let result = result else {
                Logging.log("Create Action", ["Result": "Upload", "Success": false])
                let alert = UIAlertController(title: "Oops!", message: "Something went wrong. Please try again.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            Logging.log("Create Action", ["Result": "Upload", "Success": true])
            let content = PendingContent(assets: [result])
            content.type = .upload
            TabBarController.instance?.showReview(content: content, source: "Upload (Unsupported Device Create Button)")
        }
    }

    // MARK: - UITabBarControllerDelegate

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if let vc = viewController as? ContentViewController, vc.view.window != nil {
            vc.scrollToTop()
        } else if let vc = viewController as? DiscoverViewController, vc.view.window != nil {
            vc.scrollToTop()
        } else if let vc = viewController as? TopArtistsViewController, vc.view.window != nil {
            vc.scrollToTop()
        } else if let vc = viewController as? NotificationsViewController, vc.view.window != nil {
            vc.scrollToTop()
        } else if let vc = viewController as? ProfileViewController, vc.view.window != nil {
            vc.scrollToTop()
        } else if let vc = viewController as? PublicRequestsViewController, vc.view.window != nil {
            vc.scrollToTop()
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        switch viewController {
        case is ContentViewController:
            Logging.debug("Tab Selected", ["Tab": "Feed"])
        case is DiscoverViewController:
            Logging.debug("Tab Selected", ["Tab": "Search"])
        case is NotificationsViewController:
            Logging.debug("Tab Selected", ["Tab": "Notifications"])
        case is ProfileViewController:
            Logging.debug("Tab Selected", ["Tab": "Profile"])
        case is PublicRequestsViewController:
            Logging.debug("Tab Selected", ["Tab": "Public Requests"])
        default:
            break
        }
        
        if viewController is ProfileViewController {
            TabBarController.instance?.tooltip.hideAnimated()
        } else if Recorder.instance.composer != nil && SettingsManager.shouldShowNewBadge(for: "plus_button") {
            TabBarController.instance?.tooltip.show()
        }
    }

    // MARK: - Private

    private static var pendingCall: (() -> ())?

    private var creationButton: UIButton!
    private var profileImageURL: URL?

    private let imagePicker = UIImagePickerController()
    private let networkManager = NetworkReachabilityManager()
    private let networkAlert = UIAlertController(
        title: "Connection Error 😬",
        message: "Please check your internet connection.",
        preferredStyle: .alert)
    private var statusIndicatorView: StatusIndicatorView!

    private func checkFacebookFriends(callback: @escaping ((Bool) -> ())) {
        guard let request = FBSDKGraphRequest(graphPath: "/me/friends", parameters: ["fields": "id,name,picture.type(normal){url}"]) else {
            callback(false)
            return
        }
        request.start { connection, result, error in
            guard let data = (result as? DataType)?["data"] as? [DataType], !data.isEmpty else {
                callback(false)
                return
            }
            Logging.log("Find Facebook Friends", ["Result": data.count])
            callback(true)
        }
    }

    @objc private dynamic func creationButtonTapped() {
        if Recorder.instance.composer == nil {
            Logging.log("Device Too Old Creation Tapped")
            self.imagePicker.sourceType = .photoLibrary
            self.imagePicker.mediaTypes = [kUTTypeMovie as String]
            self.present(self.imagePicker, animated: true)
        } else {
            SettingsManager.reportNewBadgeInteraction(for: "plus_button")
            self.tooltip.hideAnimated()
            self.showCreationPicker(source: "Create Button")
        }
    }

    private func handleSessionChanged() {
        guard
            let item = self.tabBar.items?[Tab.profile.rawValue],
            let session = BackendClient.api.session,
            session.hasBeenOnboarded
            else { return }
        item.badgeValue = nil
        BackendClient.api.sessionChanged.removeListener(self)
    }

    private func newCreation(source: String) -> CreationViewController {
        Logging.debug("Entering Creation", ["Source": source])
        let c = self.storyboard!.instantiateViewController(withIdentifier: "Creation") as! CreationViewController
        c.quality = SettingsManager.recordQuality
        c.source = source
        return c
    }

    private func resetProfileImage() {
        self.tabBar.items?[4].image = #imageLiteral(resourceName: "person")
        self.profileImageURL = nil
    }

    private func updateNetworkAlert() {
        guard let manager = self.networkManager else {
            return
        }
        switch manager.networkReachabilityStatus {
        case .notReachable:
            if self.networkAlert.view.window == nil {
                self.present(self.networkAlert, animated: true)
            }
        default:
            self.networkAlert.dismiss(animated: true)
        }
    }

    private func updateProfileImage() {
        let barItem = self.tabBar.items![4]
        guard let session = BackendClient.api.session, let imageURL = session.imageURL else {
            self.resetProfileImage()
            return
        }
        guard imageURL != self.profileImageURL else {
            return
        }
        self.profileImageURL = imageURL
        ImageDownloader.default.download(URLRequest(url: imageURL), completion: {
            guard let image = $0.result.value else {
                self.resetProfileImage()
                return
            }
            let size = CGSize(width: 28, height: 28)
            let imageRatio = image.size.width / image.size.height
            let factor = imageRatio > 1 ? size.height / image.size.height : size.width / image.size.width
            let scaledSize = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            let origin = CGPoint(x: (size.width - scaledSize.width) / 2, y: (size.height - scaledSize.height) / 2)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let context = UIGraphicsGetCurrentContext()!
            defer { UIGraphicsEndImageContext() }
            context.interpolationQuality = .high
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            UIBezierPath(roundedRect: rect, cornerRadius: size.width / 2).addClip()
            image.draw(in: CGRect(origin: origin, size: scaledSize))
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect)
            let roundedImageSelected = UIGraphicsGetImageFromCurrentImageContext()!
            context.clear(rect)
            roundedImageSelected.draw(at: .zero, blendMode: .normal, alpha: 0.6)
            barItem.image = UIGraphicsGetImageFromCurrentImageContext()!.withRenderingMode(.alwaysOriginal)
            barItem.selectedImage = roundedImageSelected.withRenderingMode(.alwaysOriginal)
        })
    }
}

private func loadVC<T: UIViewController>(_ type: T.Type) -> T? {
    let typeName = String(describing: type)
    guard let any = Bundle.main.loadNibNamed(typeName, owner: nil, options: nil)?.first else {
        return nil
    }
    return any as? T
}
