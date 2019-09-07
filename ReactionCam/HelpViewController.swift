import UIKit
import XLActionController

class HelpViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var messageField: UITextView!
    @IBOutlet weak var keyboardHeight: NSLayoutConstraint!

    var email: String?

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        NotificationCenter.default.addObserver(self, selector: #selector(HelpViewController.keyboardEvent), name: .UIKeyboardWillChangeFrame, object: nil)
        self.messageField.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        self.messageField.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
    }

    @IBAction func backTapped(_ sender: Any) {
        self.dismiss(animated: true)
    }

    @IBAction func sendTapped(_ sender: Any) {
        self.messageField.resignFirstResponder()
        let text = self.messageField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            let alert = UIAlertController(title: "Oops!", message: "Please enter a valid message.", preferredStyle: .alert)
            alert.addCancel(title: "Got it") {
                self.messageField.becomeFirstResponder()
            }
            self.present(alert, animated: true)
            return
        }

        // This condition ensures that people don't message with unsolvable problems like Old Device users that can't record
        if BackendClient.api.session != nil, Recorder.instance.composer != nil {
            self.sendMessage(text)
        } else if let email = self.email ?? BackendClient.api.session?.email  {
            self.sendEmail(text, email: email)
        } else {
            let alert = UIAlertController(title: "Want to get a reply?", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "No", style: .destructive) { _ in
                self.sendEmail(text)
            })
            alert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
                let subalert = UIAlertController(title: "What's your email?", message: nil, preferredStyle: .alert)
                subalert.addTextField(configurationHandler: { field in
                    field.keyboardAppearance = .dark
                    field.keyboardType = .emailAddress
                    field.placeholder = "email@address.com"
                })
                subalert.addAction(UIAlertAction(title: "That's me I promise!", style: .default, handler: { _ in
                    let email = subalert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces)
                    self.sendEmail(text, email: email)
                }))
                self.present(subalert, animated: true)
            })
            self.present(alert, animated: true)
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.messageField.becomeFirstResponder()
        return false
    }

    // MARK: - Private

    private var statusIndicatorView: StatusIndicatorView!

    @objc private dynamic func keyboardEvent(notification: NSNotification) {
        self.view.layoutIfNeeded()
        let info = notification.userInfo!
        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationCurve(UIViewAnimationCurve(rawValue: (info[UIKeyboardAnimationCurveUserInfoKey] as! NSNumber).intValue)!)
        UIView.setAnimationDuration((info[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue)
        UIView.setAnimationBeginsFromCurrentState(true)
        let frame = info[UIKeyboardFrameEndUserInfoKey] as! CGRect
        self.keyboardHeight.constant = 16 - (frame.minY - UIApplication.shared.keyWindow!.bounds.height)
        self.view.layoutIfNeeded()
        UIView.commitAnimations()
    }

    private func sendEmail(_ message: String, email: String? = nil) {
        Intent.sendFeedback(message: message, email: email).perform(BackendClient.api)
        let title: String
        if let email = email, !email.isEmpty {
            title = "Sent, we'll get back to you shortly!"
        } else {
            title = "Sent, thank you!"
        }
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.dismiss(animated: true)
        })
        self.present(alert, animated: true)
    }

    private func sendMessage(_ message: String) {
        self.statusIndicatorView.showLoading()
        MessageService.instance.createThread(identifier: "reaction.cam") { thread, error in
            self.statusIndicatorView.hide()
            guard let thread = thread, error == nil else {
                self.sendEmail(message, email: self.email ?? BackendClient.api.session?.email)
                return
            }
            do {
                try thread.message(type: .text, text: message + (self.email != nil ? "\n\nEmail: \(self.email!)" : ""))
            } catch {
                self.sendEmail(message, email: self.email ?? BackendClient.api.session?.email)
                return
            }
            let alert = UIAlertController(title: "Sent, we'll get back to you shortly!", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self.dismiss(animated: true)
            })
            self.present(alert, animated: true)
        }
    }
}

extension HelpViewController {
    static func showHelp(presenter: UIViewController, email: String? = nil) {
        let sheet = ActionSheetController(title: "Support")
        sheet.addAction(Action("Help Center", style: .default) { _ in
            Logging.log("Help Options", ["Action": "FAQ"])
            UIApplication.shared.open(SettingsManager.helpURL, options: [:])
        })
        sheet.addAction(Action("Message @reaction.cam", style: .default) { _ in
            Logging.log("Help Options", ["Action": "Message"])
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let messageUs = storyboard.instantiateViewController(withIdentifier: "Help") as! HelpViewController
            messageUs.email = email
            presenter.present(messageUs, animated: true)
        })
        sheet.addCancel()
        presenter.present(sheet, animated: true)
    }
}
