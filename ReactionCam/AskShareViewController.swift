import MessageUI
import UIKit

class AskShareViewController: UIViewController, MFMessageComposeViewControllerDelegate {
    
    @IBOutlet weak var feedbackView: MaterialView!
    @IBOutlet weak var likeView: MaterialView!
    @IBOutlet weak var shareView: MaterialView!
    @IBOutlet weak var hiView: MaterialView!
    @IBOutlet weak var spinView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.insertSubview(self.cheerView, at: 0)
        self.cheerView.frame = self.view.bounds
        self.cheerView.config.particle = .confetti
        self.cheerView.alpha = 0
        self.cheerView.start()

        self.hiView.alpha = 0
        self.likeView.alpha = 0
        
        SettingsManager.didAskToShare = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.hiView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0.5, options: .curveEaseIn, animations: {
            self.hiView.isHidden = false
            self.hiView.alpha = 1
        })
        
        UIView.animate(withDuration: 2.2, delay: 0, options: [.curveLinear, .repeat], animations: {
            self.spinView.transform = self.spinView.transform.concatenating(CGAffineTransform(rotationAngle: CGFloat.pi))
        })

    }
    
    @IBAction func closeTapped(_ sender: Any) {
        Logging.log("Ask Share Like", ["Choice": "Close"])
        self.dismiss(animated: true)
    }
    
    @IBAction func dislikeTapped(_ sender: Any) {
        Logging.log("Ask Share Like", ["Choice": "No"])
        
        self.feedbackView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        self.likeView.hideAnimated() {
            self.feedbackView.isHidden = false
            // Make the avatar shrink while it's being touched.
            UIView.animate(withDuration: 1,
                           delay: 0.0,
                           usingSpringWithDamping: 0.6,
                           initialSpringVelocity: 14,
                           options: .allowUserInteraction,
                           animations: {
                            self.feedbackView.transform = .identity
            },
                           completion: nil
            )
        }
        self.feedbackView.showAnimated()
    }
    
    @IBAction func hiTapped(_ sender: Any) {
        self.hiView.hideAnimated {
            UIView.animate(withDuration: 0.5, delay: 0.3, options: .curveEaseIn, animations: {
                self.likeView.isHidden = false
                self.likeView.alpha = 1
            })
        }
    }
    
    @IBAction func likeTapped(_ sender: Any) {
        Logging.log("Ask Share Like", ["Choice": "Yes"])
        
        self.shareView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        self.likeView.hideAnimated() {
            UIView.animate(withDuration: 0.3) {
                self.cheerView.alpha = 0.5
            }
            
            self.shareView.isHidden = false
            // Make the avatar shrink while it's being touched.
            UIView.animate(withDuration: 1.8,
                           delay: 0.0,
                           usingSpringWithDamping: 0.5,
                           initialSpringVelocity: 18,
                           options: .allowUserInteraction,
                           animations: {
                            self.shareView.transform = .identity
            },
                           completion: nil
            )
        }
    }
    
    @IBAction func feedbackTapped(_ sender: Any) {
        Logging.log("Ask Share Feedback", ["Choice": "Yes"])
        self.dismiss(animated: true) {
            DispatchQueue.main.async {
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let messageVC = storyboard.instantiateViewController(withIdentifier: "Help") as! HelpViewController
                TabBarController.instance?.present(messageVC, animated: true)
            }
        }
    }
    
    @IBAction func noRatingTapped(_ sender: Any) {
        Logging.log("Ask Share Invite", ["Choice": "No"])
        self.dismiss(animated: true)
    }
    
    @IBAction func noFeedbackTapped(_ sender: Any) {
        Logging.log("Ask Share Feedback", ["Choice": "No"])
        self.dismiss(animated: true)
    }
    
    @IBAction func shareTapped(_ sender: Any) {
        Logging.log("Ask Share Invite", ["Choice": "Yes"])
        let body = SettingsManager.shareChannelCopy(account: BackendClient.api.session)
        guard  MFMessageComposeViewController.canSendText() else {
            let vc = UIActivityViewController(activityItems: [DynamicActivityItem(body)], applicationActivities: nil)
            vc.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
            vc.completionWithItemsHandler = {
                _, completed, _, _ in
                if completed {
                    SettingsManager.userDidShare = true
                }
                Logging.log("Ask Share Message", ["Source": "ActivityView", "Result": completed ? "Success" : "Cancel"])
                self.dismiss(animated: true)
            }
            vc.configurePopover(sourceView: self.shareView)
            self.present(vc, animated: true)
            return
        }
        let vc = MFMessageComposeViewController()
        vc.body = body
        vc.messageComposeDelegate = self
        self.present(vc, animated: true)
    }
    
    // MARK: - MFMessageComposeViewControllerDelegate
    
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        let resultString: String
        switch result {
        case .sent:
            resultString = "Success"
            SettingsManager.userDidShare = true
        case .failed:
            resultString = "Failed"
        case .cancelled:
            resultString = "Cancel"
        }
        Logging.log("Ask Share Message", ["Source": "MessageView", "Result": resultString])
        
        controller.dismiss(animated: true)
        self.dismiss(animated: true)
    }
    
    private let cheerView = CheerView()
}
