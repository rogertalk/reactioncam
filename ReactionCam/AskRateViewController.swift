import iRate
import UIKit

class AskRateViewController: UIViewController {

    @IBOutlet weak var feedbackView: MaterialView!
    @IBOutlet weak var likeView: MaterialView!
    @IBOutlet weak var rateView: MaterialView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.insertSubview(self.cheerView, at: 0)
        self.cheerView.frame = self.view.bounds
        self.cheerView.config.particle = .confetti
        self.cheerView.alpha = 0
        self.cheerView.start()

        self.likeView.transform = CGAffineTransform(translationX: -(self.view.bounds.width + 170), y: 0)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Make the avatar shrink while it's being touched.
        UIView.animate(withDuration: 0.9,
                       delay: 0.0,
                       usingSpringWithDamping: 0.55,
                       initialSpringVelocity: 12,
                       options: [.allowUserInteraction, .curveEaseIn],
                       animations: {
                        self.likeView.transform = .identity
        },
                       completion: nil
        )
    }

    @IBAction func closeTapped(_ sender: Any) {
        Logging.log("Ask Like", ["Choice": "Close"])
        self.dismiss(animated: true)
    }

    @IBAction func dislikeTapped(_ sender: Any) {
        Logging.log("Ask Like", ["Choice": "No"])
        iRate.sharedInstance().declinedThisVersion = true

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

    @IBAction func likeTapped(_ sender: Any) {
        Logging.log("Ask Like", ["Choice": "Yes"])

        self.rateView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        self.likeView.hideAnimated() {
            self.cheerView.showAnimated()

            self.rateView.isHidden = false
            // Make the avatar shrink while it's being touched.
            UIView.animate(withDuration: 0.8,
                           delay: 0.0,
                           usingSpringWithDamping: 0.5,
                           initialSpringVelocity: 18,
                           options: .allowUserInteraction,
                           animations: {
                            self.rateView.transform = .identity
            },
                           completion: nil
            )
        }
    }

    @IBAction func feedbackTapped(_ sender: Any) {
        Logging.log("Ask Feedback", ["Choice": "Yes"])
        self.dismiss(animated: true) {
            DispatchQueue.main.async {
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let messageVC = storyboard.instantiateViewController(withIdentifier: "Help") as! HelpViewController
                TabBarController.instance?.present(messageVC, animated: true)
            }
        }
    }

    @IBAction func noRatingTapped(_ sender: Any) {
        Logging.log("Ask Rate", ["Choice": "No"])
        self.dismiss(animated: true)
    }

    @IBAction func noFeedbackTapped(_ sender: Any) {
        Logging.log("Ask Feedback", ["Choice": "No"])
        self.dismiss(animated: true)
    }

    @IBAction func rateTapped(_ sender: Any) {
        Logging.log("Ask Rate", ["Choice": "Yes"])

        iRate.sharedInstance().ratedThisVersion = true
        iRate.sharedInstance().openRatingsPageInAppStore()
        self.dismiss(animated: true)
    }

    private let cheerView = CheerView()
}
