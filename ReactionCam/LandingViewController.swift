import AVFoundation
import Crashlytics
import FBSDKLoginKit
import SafariServices
import UIKit


class LandingViewController: UIViewController,
    SFSafariViewControllerDelegate,
    UIScrollViewDelegate
{

    @IBOutlet weak var controlsView: UIView!
    @IBOutlet weak var linkLabel: UILabel!
    @IBOutlet weak var linkView: UIView!
    @IBOutlet weak var pageControl: UIPageControl!
    @IBOutlet weak var panesStackView: UIStackView!
    @IBOutlet weak var playerContainer: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var signUpButton: HighlightButton!
    @IBOutlet weak var spamLabel: UILabel!

    var backgroundImage: UIImage?
    var deepLinkedContent: Content?

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(patternImage: #imageLiteral(resourceName: "emojiBackground")).withAlphaComponent(0.1)

        self.scrollView.delegate = self

        self.linkLabel.font = UIFont.systemFont(ofSize: 33, weight: .semibold)

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.pageControl.numberOfPages = Int(round(self.panesStackView.frame.width / scrollView.frame.width))

        self.playerContainer.insertSubview(self.cheerView, belowSubview: self.spamLabel)
        self.cheerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.cheerView.frame = self.playerContainer.bounds
        self.cheerView.config.particle = .confetti
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.setUpBackgroundMedia()
        if let session = BackendClient.api.session {
            guard SetDemoViewController.shouldAskLater || (session.birthday != nil && session.gender != nil) else {
                let vc = self.storyboard?.instantiateViewController(withIdentifier: "SetDemo")
                self.present(vc!, animated: true)
                return
            }
            self.finishOnboarding()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        self.displayLink?.isPaused = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.playerLayer?.frame = self.playerContainer.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        self.displayLink?.isPaused = false
    }

    @IBAction func logInTapped(_ sender: Any) {
        Logging.log("Start Screen", ["Action": "LogIn"])
        guard !SettingsManager.isTainted else {
            Logging.log("Start Screen Banned", ["Action": "Log In"])
            let alert = UIAlertController(
                title: "You have been banned from Reaction.cam",
                message: "If you believe this is an error, please email yo@reaction.cam", preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
            return
        }
        let challenge = self.storyboard?.instantiateViewController(withIdentifier: "Challenge") as! ChallengeViewController
        challenge.mode = .logIn
        self.present(challenge, animated: true)
    }

    @IBAction func nextTapped(_ sender: Any) {
        self.scrollView.setContentOffset(CGPoint(x: self.scrollView.contentOffset.x + self.scrollView.frame.width, y: 0), animated: true)
    }

    @IBAction func signUpArtistTapped(_ sender: Any) {
        Logging.log("Start Screen", ["Action": "Artist SignUp"])
        let alert = UIAlertController(
            title: "Are you an artist, music producer, or work for a label?",
            message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
            Logging.log("Start Screen Artist", ["Action": "Yes"])
            let vc = SFSafariViewController(url: SettingsManager.helpArtistsSignUpURL)
            self.webController = vc
            vc.preferredBarTintColor = UIColor.uiBlack
            vc.preferredControlTintColor = UIColor.white
            vc.delegate = self
            self.present(vc, animated: true)
        })
        let action = UIAlertAction(title: "No", style: .default) { _ in
            Logging.log("Start Screen Artist", ["Action": "No"])
            self.signUpButton.pulse()
        }
        alert.addAction(action)
        alert.preferredAction = action
        self.present(alert, animated: true)
    }

    @IBAction func signUpTapped(_ sender: Any) {
        Logging.log("Start Screen", ["Action": "SignUp"])
        guard !SettingsManager.isTainted else {
            Logging.log("Start Screen Banned", ["Action": "Sign Up"])
            let alert = UIAlertController(
                title: "You have been banned from Reaction.cam",
                message: "If you believe this is an error, please email yo@reaction.cam", preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
            return
        }
        self.statusIndicatorView.showLoading()
        Intent.register(username: nil, password: nil, birthday: nil, gender: nil).perform(BackendClient.api) { _ in
            self.statusIndicatorView.hide()
            self.finishOnboarding()
        }
    }

    @IBAction func termsOfUseTapped(_ sender: Any) {
        Logging.log("Start Screen", ["Action": "Terms"])
        let vc = SFSafariViewController(url: URL(string: "https://www.reaction.cam/terms")!)
        self.webController = vc
        vc.preferredBarTintColor = UIColor.uiBlack
        vc.preferredControlTintColor = UIColor.white
        vc.delegate = self
        self.present(vc, animated: true)
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let dx = scrollView.contentOffset.x
        self.pageControl.currentPage = Int(round(dx / scrollView.frame.width))
    }

    // MARK: - SFSafariViewControllerDelegate

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        self.webController = nil
    }

    // MARK: - Private

    private let cheerView = CheerView()

    private var didSetUpBackgroundMedia = false
    private var displayLink: CADisplayLink?
    private var imageView: UIImageView?
    private var imageViewRadians = CGFloat.pi * 1.5
    private var playerLayer: AVPlayerLayer?
    private var statusIndicatorView: StatusIndicatorView!
    private var webController: SFSafariViewController?

    private func handleApplicationActiveStateChanged(active: Bool) {
        guard let player = self.playerLayer?.player else {
            return
        }
        active ? player.play() : player.pause()
    }

    @objc dynamic private func playerItemDidReachEnd() {
        guard let player = self.playerLayer?.player else {
            return
        }
        player.seek(to: kCMTimeZero)
        player.play()
    }

    private func finishOnboarding() {
        guard BackendClient.api.session != nil else {
            return
        }
        Logging.debug("Finish Onboarding")
        // PARTY!
        self.view.addSubview(self.playerContainer)
        self.scrollView.isHidden = true
        self.spamLabel.isHidden = false
        self.cheerView.start()
        AppDelegate.requestNotificationPermissions(presentAlertWith: self, source: "Landing") { success in
            DispatchQueue.main.async {
                // Clean up event handlers.
                NotificationCenter.default.removeObserver(self)
                AppDelegate.applicationActiveStateChanged.removeListener(self)
                // Stop animations.
                self.cheerView.stop()
                self.displayLink?.invalidate()
                self.displayLink = nil
                self.playerLayer?.player?.replaceCurrentItem(with: nil)
                // Show the logged in UI.
                let vc = self.storyboard!.instantiateViewController(withIdentifier: "RootNavigation")
                guard let window = self.view.window ?? UIApplication.shared.keyWindow else {
                    return
                }
                window.rootViewController = vc
            }
        }
    }

    @objc private func updateImageView() {
        guard let view = self.imageView else {
            return
        }
        let r = self.imageViewRadians + self.scrollView.contentOffset.x * 0.001
        let scale = 1.2 + sin(r) * 0.2
        let dx = cos(r) * 50
        view.transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: dx, y: 0)
        self.imageViewRadians += 0.003
    }

    private func setUpBackgroundMedia() {
        guard !self.didSetUpBackgroundMedia else {
            return
        }
        self.didSetUpBackgroundMedia = true
        if let image = self.backgroundImage {
            let view = UIImageView(image: image)
            view.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            view.contentMode = .scaleAspectFill
            view.frame = self.playerContainer.bounds
            self.playerContainer.insertSubview(view, at: 0)
            self.imageView = view
            let link = CADisplayLink(target: self, selector: #selector(LandingViewController.updateImageView))
            link.add(to: .current, forMode: .commonModes)
            self.displayLink = link
            self.scrollView.isHidden = true
            self.controlsView.isHidden = true
            self.linkView.isHidden = false
            if let title = self.deepLinkedContent?.title {
                self.linkLabel.text = title
            }

        } else if let videoURL = Bundle.main.url(forResource: "onboardingReaction", withExtension: "mp4") {
            let item = AVPlayerItem(url: videoURL)
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .none
            player.isMuted = true
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspect
            playerLayer.frame = self.playerContainer.bounds
            self.playerContainer.layer.insertSublayer(playerLayer, at: 0)
            self.playerLayer = playerLayer
            player.play()
            AppDelegate.applicationActiveStateChanged.addListener(self, method: LandingViewController.handleApplicationActiveStateChanged)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(LandingViewController.playerItemDidReachEnd),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item)
            self.scrollView.isHidden = false
            self.linkView.isHidden = true
        }
    }
}
