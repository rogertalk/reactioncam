import UIKit

class SetUsernameViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var keyboardHeight: NSLayoutConstraint!
    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var urlLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        self.usernameField.becomeFirstResponder()
        self.usernameField.delegate = self
        self.usernameField.autocapitalizationType = .none
        self.usernameField.setPlaceholder(text: "username", color: .darkGray)

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        self.urlLabel.text = ""
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(SetUsernameViewController.keyboardEvent), name: .UIKeyboardWillChangeFrame, object: nil)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    @IBAction func confirmTapped(_ sender: Any) {
        Logging.log("Username Screen", ["Action": "Confirm"])
        self.finish()
    }

    @IBAction func usernameEditingChanged(_ sender: Any) {
        guard let username = self.identifier, !username.isEmpty else {
            self.urlLabel.text = ""
            return
        }

        self.urlLabel.text = "🔗 \(SettingsManager.getChannelURL(username: username).replacingOccurrences(of: "https://", with: ""))"
    }

    // UITextFieldDelegate

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.layoutIfNeeded()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        self.finish()
        return false
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField == self.usernameField,
            range.location == 0,
            !(string.first?.isLetter ?? true) {
            let alert = UIAlertController(title: "Oops! 😅", message: "Usernames must start with a letter.", preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
            return false
        }
        return true
    }
    
    // MARK: - Private

    private var statusIndicatorView: StatusIndicatorView!

    private var identifier: String? {
        let trim = CharacterSet.whitespacesAndNewlines.union(["@"])
        guard let identifier = self.usernameField.text?.trimmingCharacters(in: trim).lowercased(), !identifier.isEmpty else {
            return nil
        }
        return identifier.replacingOccurrences(of: " ", with: "")
    }

    @objc private dynamic func keyboardEvent(notification: NSNotification) {
        guard let windowHeight = UIApplication.shared.keyWindow?.bounds.height, let view = self.view else {
            return
        }
        view.layoutIfNeeded()
        let info = notification.userInfo!
        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationCurve(UIViewAnimationCurve(rawValue: (info[UIKeyboardAnimationCurveUserInfoKey] as! NSNumber).intValue)!)
        UIView.setAnimationDuration((info[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue)
        UIView.setAnimationBeginsFromCurrentState(true)
        let frame = info[UIKeyboardFrameEndUserInfoKey] as! CGRect
        self.keyboardHeight?.constant = -(frame.minY - windowHeight) + 40
        view.layoutIfNeeded()
        UIView.commitAnimations()
    }

    private func finish() {
        guard let username = self.identifier, !username.isEmpty else {
            Logging.warning("Sign Up Alert", ["Info": "Invalid username", "Username": self.usernameField.text ?? ""])
            let alert = UIAlertController(title: "Invalid username", message: "Username must start with a letter and cannnot have whitespaces.", preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
            return
        }
        self.statusIndicatorView.showLoading()
        Intent.updateProfileUsername(username: username).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            guard $0.successful else {
                let message: String
                switch $0.code {
                case 400:
                    message = "That username is not valid. Try another one!\n\nUsername must start with a letter and can only contain letters, numbers, and . _ -"
                case 409:
                    message = "That username is already taken. Try another one!"
                default:
                    message = "Something went wrong. Please try again."
                }
                let alert = UIAlertController(title: "Oops!", message: message, preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            guard let vc = self.storyboard?.instantiateViewController(withIdentifier: "RootNavigation") else {
                return
            }
            self.present(vc, animated: true)
        }
    }
}
