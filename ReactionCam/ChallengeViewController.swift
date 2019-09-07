import Crashlytics
import UIKit

class ChallengeViewController: UIViewController, UITextFieldDelegate {

    enum State {
        case enterIdentifier, enterCode, enterPassword, enterUsernamePassword
    }

    enum Mode {
        case connectEmail, forgotUsernamePassword, logIn, signUp
    }

    @IBOutlet weak var centerXConstraint: NSLayoutConstraint!
    @IBOutlet weak var dontWorryLabel: UILabel!
    @IBOutlet weak var facebookConnectButton: HighlightButton!
    @IBOutlet weak var facebookSpamLabel: UILabel!
    @IBOutlet weak var helpButton: UIButton!
    @IBOutlet weak var identifierConfirmButton: HighlightButton!
    @IBOutlet weak var identifierField: UITextField!
    @IBOutlet weak var identifierLabel: UILabel!
    @IBOutlet weak var identifierTitle: UILabel!
    @IBOutlet weak var secretConfirmButton: HighlightButton!
    @IBOutlet weak var secretField: UITextField!
    @IBOutlet weak var secretLabel: UILabel!
    @IBOutlet weak var secretTitle: UILabel!
    @IBOutlet weak var termsButton: UIButton!
    @IBOutlet weak var urlLabel: UILabel!
    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var keyboardHeight: NSLayoutConstraint!
    @IBOutlet weak var waitTimeLabel: UILabel!

    var mode: Mode = .signUp

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.identifierField.delegate = self
        self.secretField.delegate = self

        self.state = .enterIdentifier

        NotificationCenter.default.addObserver(self, selector: #selector(ChallengeViewController.keyboardEvent), name: .UIKeyboardWillChangeFrame, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
    }

    // MARK: - Actions

    @IBAction func backTapped(_ sender: Any) {
        Logging.log("Sign Up Screen", ["Action": "Back"])
        self.state = .enterIdentifier
    }

    @IBAction func closeTapped(_ sender: Any) {
        Logging.log("Sign Up Screen", ["Action": "Close"])
        self.dismiss(animated: true)
    }

    @IBAction func facebookConnectTapped(_ sender: Any) {
        self.facebookConnectButton.isLoading = true
        AppDelegate.connectFacebook(presenter: self) { success in
            self.facebookConnectButton.isLoading = false
            Answers.logLogin(withMethod: "Facebook", success: NSNumber(value: success), customAttributes: [:])
            if success {
                self.dismiss(animated: true)
            }
        }
    }

    @IBAction func identifierConfirmTapped(_ sender: Any) {
        self.requestChallenge()
    }

    @IBAction func helpTapped(_ sender: Any) {
        Logging.log("Sign Up Screen", ["Action": "Help"])
        switch self.state {
        case .enterCode:
            let alert = UIAlertController(
                title: "Have you checked your Spam or Junk folders for the email?",
                message: "If you don't see an email in your inbox, make sure the email address listed above is correct and check your Spam or Junk mail folders. This email is sent from yo@reaction.cam 🕵️", preferredStyle: .alert)
            alert.addCancel(title: "Found it!") {
                Logging.log("Sign Up Screen Help", ["Action": "Found It"])
            }
            alert.addAction(UIAlertAction(title: "Send email again", style: .default) { _ in
                Logging.log("Sign Up Screen Help", ["Action": "Send Again"])
                self.secretConfirmButton.isLoading = true
                Intent.requestChallenge(identifier: self.identifier!, preferPhoneCall: false).perform(BackendClient.api) { _ in
                    self.secretConfirmButton.isLoading = false
                }
                self.setupCountdownTimer()
                self.secretLabel.text = "We sent another email, please check the Spam or Junk folders."
                self.secretField.isEnabled = true
                self.secretField.text = ""
                self.secretField.becomeFirstResponder()
            })
            alert.addAction(UIAlertAction(title: "I have a different issue", style: .default) { _ in
                Logging.log("Sign Up Screen Help", ["Action": "Feedback"])
                if self.state == .enterCode {
                    HelpViewController.showHelp(presenter: self, email: self.identifier)
                } else {
                    HelpViewController.showHelp(presenter: self)
                }
                self.identifierField.text = ""
                self.state = .enterIdentifier
            })
            self.present(alert, animated: true)
        case .enterPassword:
            self.mode = .forgotUsernamePassword
            self.identifierField.text = ""
            self.state = .enterIdentifier
        default:
            break
        }
    }

    @IBAction func secretConfirmTapped(_ sender: Any) {
        self.finish()
    }

    @IBAction func termsOfUseTapped(_ sender: Any) {
        Logging.log("Sign Up Screen", ["Action": "Terms"])
        UIApplication.shared.open(URL(string: "https://www.reaction.cam/terms")!, options: [:])
    }

    @objc func updateWaitTimeLabel() {
        guard let referenceDate = self.startCountdownDate else {
            return
        }

        let secondsElapsed = Int(floor(Date().timeIntervalSince(referenceDate)))
        if secondsElapsed > self.waitTime {
            self.countdownTimer?.invalidate()
            self.countdownTimer = nil
            UIView.animate(withDuration: 0.2, animations: {
                self.waitTimeLabel.alpha = 0
            }, completion: { _ in
                UIView.animate(withDuration: 0.3, animations: {
                    self.waitTimeLabel.isHidden = true
                    self.helpButton.isHidden = false
                })
            })
            return
        }
        if secondsElapsed > 10 {
            let formatter = DateComponentsFormatter()
            self.waitTimeLabel.text = String.localizedStringWithFormat(
                NSLocalizedString("Your email should arrive in less than %@", comment: "Verify email"),
                formatter.string(from: TimeInterval(self.waitTime - secondsElapsed))!)
        } else {
            self.waitTimeLabel.text = NSLocalizedString("Check your email, your code should arrive soon.", comment: "Verify email")
        }
    }

    @IBAction func usernameEditingChanged(_ sender: Any) {
        guard let username = self.usernameField.text, !username.isEmpty else {
            UIView.animate(withDuration: 0.3, animations: {
                self.urlLabel.isHidden = true
            })
            return
        }
        UIView.animate(withDuration: 0.3, animations: {
            self.urlLabel.isHidden = false
        })
        self.urlLabel.text = "🔗 \(SettingsManager.getChannelURL(username: username).replacingOccurrences(of: "https://", with: ""))"
    }

    // UITextFieldDelegate

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.layoutIfNeeded()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch self.state {
        case .enterIdentifier:
            self.requestChallenge()
        case .enterCode, .enterPassword:
            self.finish()
        case .enterUsernamePassword:
            if textField == self.usernameField {
                self.secretField.becomeFirstResponder()
            } else {
                self.finish()
            }
        }
        return true
    }

    @IBAction func identifierFieldEditingChanged(_ sender: Any) {
        if self.identifier == nil {
            self.identifierConfirmButton.isHidden = true
            switch self.mode {
            case .connectEmail:
                self.identifierTitle.text = "Verify Email"
            case .forgotUsernamePassword:
                self.identifierTitle.text = "Recover Account"
            case .logIn:
                self.identifierTitle.text = "Log In"
            case .signUp:
                self.identifierTitle.text = "Sign Up"
            }
        } else {
            self.identifierTitle.text = self.identifierField.text?.replacingOccurrences(of: " ", with: "")
            self.identifierConfirmButton.isHidden = false
        }
    }

    // MARK: - Private

    private var account: Account?
    private var startCountdownDate: Date?
    private var countdownTimer: Timer?
    private let waitTime = 60

    private var identifier: String? {
        let trim = CharacterSet.whitespacesAndNewlines.union(["@"])
        guard var identifier = self.identifierField.text?.trimmingCharacters(in: trim).lowercased(), !identifier.isEmpty else {
            return nil
        }
        if identifier.contains("@") && identifier.hasSuffix(".con") {
            identifier = String(identifier.dropLast()) + "m"
        }
        return identifier.replacingOccurrences(of: " ", with: "")
    }

    private var state: State = .enterIdentifier {
        didSet {
            var offset: CGFloat = 0
            switch self.state {
            case .enterIdentifier:
                self.secretField.resignFirstResponder()
                self.identifierField.isEnabled = true
                self.identifierConfirmButton.isHidden = self.identifier == nil
                switch self.mode {
                case .connectEmail:
                    self.identifierTitle.text = "Verify Email Address"
                    self.facebookConnectButton.isHidden = true
                    self.facebookSpamLabel.isHidden = true
                    self.identifierLabel.text = "Please enter your email:"
                    self.identifierField.setPlaceholder(text: "email@example.com", color: "797979".hexColor!)
                    self.termsButton.isHidden = true
                    self.identifierField.becomeFirstResponder()
                case .forgotUsernamePassword:
                    self.identifierTitle.text = "Recover Account"
                    self.facebookConnectButton.isHidden = true
                    self.facebookSpamLabel.isHidden = true
                    self.identifierLabel.text = "Please enter the email associated with your account:"
                    self.identifierField.setPlaceholder(text: "email@example.com", color: "797979".hexColor!)
                    self.termsButton.isHidden = true
                    self.identifierField.becomeFirstResponder()
                case .logIn:
                    self.identifierTitle.text = "Log In"
                    self.facebookConnectButton.title = "LOG IN WITH FACEBOOK"
                    self.facebookConnectButton.isHidden = false
                    self.facebookSpamLabel.isHidden = false
                    self.identifierLabel.text = "— or —"
                    self.identifierField.setPlaceholder(text: "username", color: "797979".hexColor!)
                    self.termsButton.isHidden = false
                case .signUp:
                    self.identifierTitle.text = "Sign Up"
                    self.facebookConnectButton.title = "SIGN UP WITH FACEBOOK"
                    self.facebookConnectButton.isHidden = false
                    self.facebookSpamLabel.isHidden = false
                    self.identifierLabel.text = "— or —"
                    self.identifierField.setPlaceholder(text: "email@example.com", color: "797979".hexColor!)
                    self.termsButton.isHidden = false
                }
            case .enterCode:
                self.setupCountdownTimer()
                self.helpButton.setTitle("I'm having trouble with the code", for: .normal)
                self.secretLabel.text = "A verification code has been sent to the email above.\n\nEnter the code here:"
                self.secretTitle.text = self.identifier!
                self.usernameField.isHidden = true
                self.urlLabel.isHidden = true
                self.secretField.text = ""
                self.secretField.isEnabled = true
                self.secretField.isSecureTextEntry = false
                self.secretField.keyboardType = .numberPad
                self.secretField.setPlaceholder(text: "6-digit code", color: "797979".hexColor!)
                self.secretField.becomeFirstResponder()
                offset = -self.view.frame.width
            case .enterPassword:
                self.helpButton.isHidden = false
                self.dontWorryLabel.isHidden = true
                self.waitTimeLabel.isHidden = true
                self.helpButton.setTitle("I forgot my username or password", for: .normal)
                self.secretLabel.text = "Please enter your password to log in."
                self.secretTitle.text = "@\(self.identifier!)"
                self.usernameField.isHidden = true
                self.urlLabel.isHidden = true
                self.secretField.text = ""
                self.secretField.isEnabled = true
                self.secretField.isSecureTextEntry = true
                self.secretField.keyboardType = .default
                self.secretField.setPlaceholder(text: "password 🔒", color: "797979".hexColor!)
                self.secretField.becomeFirstResponder()
                offset = -self.view.frame.width
            case .enterUsernamePassword:
                self.helpButton.isHidden = true
                self.dontWorryLabel.isHidden = false
                self.waitTimeLabel.isHidden = true
                self.usernameField.isHidden = false
                self.urlLabel.isHidden = true
                self.secretLabel.text = "Pick a good username*"
                self.secretTitle.text = self.identifier!
                self.usernameField.text = ""
                self.usernameField.isEnabled = true
                self.usernameField.isSecureTextEntry = false
                self.usernameField.keyboardType = .default
                self.usernameField.setPlaceholder(text: "username", color: "797979".hexColor!)
                self.usernameField.becomeFirstResponder()
                self.secretField.text = ""
                self.secretField.isEnabled = true
                self.secretField.isSecureTextEntry = false
                self.secretField.keyboardType = .default
                self.secretField.setPlaceholder(text: "password 🔒", color: "797979".hexColor!)
                offset = -self.view.frame.width
            }
            // Transition between identifier and secret views.
            self.view.layoutIfNeeded()
            UIView.animate(withDuration: 0.25) {
                self.centerXConstraint.constant = offset
                self.view.layoutIfNeeded()
            }
        }
    }

    @objc private dynamic func keyboardEvent(notification: NSNotification) {
        self.view.layoutIfNeeded()
        let info = notification.userInfo!
        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationCurve(UIViewAnimationCurve(rawValue: (info[UIKeyboardAnimationCurveUserInfoKey] as! NSNumber).intValue)!)
        UIView.setAnimationDuration((info[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue)
        UIView.setAnimationBeginsFromCurrentState(true)
        let frame = info[UIKeyboardFrameEndUserInfoKey] as! CGRect
        var dy = UIApplication.shared.keyWindow!.bounds.height - frame.minY
        if #available(iOS 11.0, *) {
            dy -= self.view.safeAreaInsets.bottom
        }
        self.keyboardHeight.constant = min(-dy, 0)
        self.view.layoutIfNeeded()
        UIView.commitAnimations()
    }

    private func finish() {
        Logging.log("Sign Up Screen", ["Action": "Confirm", "Step": "Secret"])

        guard let identifier = self.identifier else {
            self.state = .enterIdentifier
            return
        }

        switch self.state {
        case .enterCode:
            guard let code = self.secretField.text?.replacingOccurrences(of: " ", with: ""), code.count == 6 else {
                self.showAlert("If you don't see an email in your inbox, make sure the email address listed above is correct and check your Spam or Junk mail folders. This email is sent from yo@reaction.cam", action: "Try again", title: "You must enter a valid code") {
                    self.secretField.text = ""
                    self.secretField.becomeFirstResponder()
                }
                return
            }

            self.secretLabel.text = "Please wait while we get your account set up..."
            self.secretConfirmButton.isLoading = true
            self.secretField.isEnabled = false
            Intent.respondToChallenge(identifier: identifier, secret: code).perform(BackendClient.api) {
                self.secretConfirmButton.isLoading = false
                guard $0.successful, let session = BackendClient.api.session else {
                    var title: String = "Uh oh!"
                    let message: String
                    switch $0.code {
                    case 400:
                        title = "That doesn't look like the code we sent."
                        message = "If you don't see an email in your inbox, make sure the email address listed above is correct and check your Spam or Junk mail folders. This email is sent from yo@reaction.cam"
                    case 404:
                        Intent.requestChallenge(identifier: identifier, preferPhoneCall: false).perform(BackendClient.api) { _ in
                            self.secretConfirmButton.isLoading = false
                        }
                        self.setupCountdownTimer()
                        self.showAlert("Check your email for a new code.", action: "Email new code", title: "Code Expired ⛔️") {
                            self.secretLabel.text = "Look for the email we sent to \(identifier)."
                            self.secretField.isEnabled = true
                            self.secretField.text = ""
                            self.secretField.becomeFirstResponder()
                        }
                        return
                    case 409:
                        message = "An account with that identifier already exists."
                    default:
                        message = "We failed to validate your code at this time."
                    }
                    self.showAlert(message, action: "Try again", title: title) {
                        self.secretLabel.text = "Look for the email we sent to \(identifier)."
                        self.secretField.isEnabled = true
                        self.secretField.text = ""
                        self.secretField.becomeFirstResponder()
                    }
                    if self.account != nil {
                        Answers.logLogin(withMethod: "Email", success: false, customAttributes: [:])
                    } else {
                        Answers.logSignUp(withMethod: "Email", success: false, customAttributes: [:])
                    }
                    return
                }
                self.account = session
                if session.hasBeenOnboarded {
                    Answers.logLogin(withMethod: "Email", success: true, customAttributes: [:])
                    self.dismiss(animated: true)
                } else {
                    Answers.logSignUp(withMethod: "Email", success: true, customAttributes: [:])
                    let setUsername = self.storyboard!.instantiateViewController(withIdentifier: "SetUsername")
                    self.present(setUsername, animated: true)
                }
            }
        case .enterPassword:
            guard let password = self.secretField.text, !password.isEmpty else {
                Logging.warning("Login Alert", ["Info": "Empty password"])
                self.showInvalidCredentialsAlert()
                return
            }

            self.secretConfirmButton.isLoading = true
            Intent.logIn(username: identifier, password: password).perform(BackendClient.api) {
                self.secretConfirmButton.isLoading = false
                guard $0.successful, let session = BackendClient.api.session else {
                    switch $0.code {
                    case -1:
                        Logging.warning("Login Alert", ["Info": "Connection Error"])
                        let error = UIAlertController(
                            title: "Connection Error",
                            message: "Please check your connection and try again.",
                            preferredStyle: .alert)
                        error.addCancel(title: "OK")
                        self.present(error, animated: true)
                    default:
                        Logging.warning("Login Alert", ["Info": "Invalid credentials"])
                        self.showInvalidCredentialsAlert()
                    }
                    Answers.logLogin(withMethod: "Password", success: false, customAttributes: [:])
                    return
                }
                Answers.logLogin(withMethod: "Password", success: true, customAttributes: [:])
                if session.hasBeenOnboarded {
                    self.dismiss(animated: true)
                } else {
                    let setUsername = self.storyboard!.instantiateViewController(withIdentifier: "SetUsername")
                    self.present(setUsername, animated: true)
                }
            }
        case .enterUsernamePassword:
            guard let username = self.usernameField.text, !username.isEmpty, let password = self.secretField.text, !password.isEmpty else {
                    let error = UIAlertController(title: "Oops!", message: "Make sure all fields are complete.", preferredStyle: .alert)
                    error.addCancel(title: "OK")
                    self.present(error, animated: true)
                    return
            }
            self.secretConfirmButton.isLoading = true
            Intent.register(username: username, password: password, birthday: nil, gender: nil).perform(BackendClient.api) {
                self.secretConfirmButton.isLoading = false
                guard $0.successful else {
                    let message: String
                    switch $0.code {
                    case -1:
                        message = "Please check your connection and try again."
                    case 400:
                        message = "That username is not valid. Try another one!\n\nUsername must start with a letter and can only contain letters, numbers, and . _ -"
                    case 409:
                        message = "That username is already taken. Try another one!"
                    default:
                        message = "Something went wrong. Please try again later."
                    }
                    let error = UIAlertController(title: "Oops!", message: message, preferredStyle: .alert)
                    error.addCancel(title: "OK")
                    self.present(error, animated: true)
                    return
                }
                Answers.logSignUp(withMethod: "Password", success: false, customAttributes: [:])
                self.dismiss(animated: true)
            }
            break
        default:
            return
        }
    }

    private func requestChallenge() {
        Logging.log("Sign Up Screen", ["Action": "Confirm", "Step": "Identifier"])

        switch self.mode {
        case .connectEmail, .forgotUsernamePassword, .signUp:
            guard let identifier = self.identifier, identifier.contains("@") else {
                Logging.warning("Sign Up Alert", ["Info": "Invalid Email", "Identifier": self.identifierField.text ?? ""])
                self.showAlert("Please insert a valid Email address to continue.", title: "Invalid Email")
                return
            }
            let emailAlert = UIAlertController(
                title: "EMAIL CONFIRMATION:\n\n\(identifier)\n\nIs your email above correct?",
                message: nil,
                preferredStyle: .alert)
            emailAlert.addCancel(title: "Edit") {
                self.identifierField.isEnabled = true
                self.identifierField.becomeFirstResponder()
            }
            emailAlert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
                if self.mode == .signUp {
                    // TODO we should store the email better...
                    Logging.info("User Entered Email", ["Email": identifier])
                    self.state = .enterUsernamePassword
                } else {
                    self.identifierConfirmButton.isLoading = true
                    Intent.requestChallenge(identifier: identifier, preferPhoneCall: false).perform(BackendClient.api) {
                        self.identifierConfirmButton.isLoading = false
                        guard $0.successful else {
                            let logIdentifier = self.identifierField.text ?? ""
                            let title: String, message: String
                            switch $0.code {
                            case -1:
                                Logging.warning("Sign Up Alert", ["Info": "Connection Error", "Identifier": logIdentifier])
                                title = "Connection Error"
                                message = "Please check your connection and try again."
                            case 400:
                                Logging.warning("Sign Up Alert", ["Info": "Invalid Identifier", "Identifier": logIdentifier])
                                title = "Invalid Email"
                                message = "That doesn't look like a valid Email address."
                            case 403:
                                Logging.warning("Sign Up Alert", ["Info": "Unauthorized", "Identifier": logIdentifier])
                                title = "Not Authorized"
                                message = "That email has not been authorized."
                            case 500, 502:
                                Logging.danger("Sign Up Alert", ["Info": "Server Error (\($0.code))", "Identifier": logIdentifier])
                                title = "Unknown Error"
                                message = "Something went wrong. Please try again later."
                            default:
                                Logging.warning("Sign Up Alert", ["Info": "Unknown Error", "Identifier": logIdentifier])
                                title = "Unknown Error"
                                message = "Something went wrong. Please check your email and internet connection."
                            }
                            self.showAlert(message, title: title) {
                                self.state = .enterIdentifier
                            }
                            return
                        }
                        self.account = ($0.data?["account"] as? DataType).flatMap(AccountBase.init(data:))
                        self.state = .enterCode
                    }
                }
            })
            self.identifierConfirmButton.isLoading = true
            self.identifierField.isEnabled = false
            let when = DispatchTime.now() + 2
            DispatchQueue.main.asyncAfter(deadline: when) {
                self.identifierConfirmButton.isLoading = false
                self.present(emailAlert, animated: true)
            }
        case .logIn:
            guard let identifier = self.identifier, !identifier.isEmpty else {
                Logging.warning("Log In Alert", ["Info": "Invalid Username", "Identifier": self.identifierField.text ?? ""])
                self.showAlert("Please insert a valid Username to continue.", title: "Invalid Username")
                return
            }
            self.identifierField.isEnabled = false
            self.state = .enterPassword
        }
    }

    private func setupCountdownTimer() {
        // Invalidate any previously running timer and start a new one
        self.countdownTimer?.invalidate()
        self.helpButton.isHidden = true
        self.waitTimeLabel.isHidden = false
        self.dontWorryLabel.isHidden = true
        self.waitTimeLabel.alpha = 1
        self.startCountdownDate = Date()
        self.updateWaitTimeLabel()
        self.countdownTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(ChallengeViewController.updateWaitTimeLabel), userInfo: nil, repeats: true)
    }

    private func showAlert(_ message: String, action: String = "OK", title: String = "Uh oh!", handler: (() -> ())? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: action, style: .cancel) { _ in handler?() })
        self.present(alert, animated: true)
    }

    private func showInvalidCredentialsAlert() {
        let alert = UIAlertController(
            title: "Wrong Username or Password",
            message: "You can only log in if you already have an account. 💁",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Sign up for a new account", style: .default) { _ in
            self.mode = .signUp
            self.identifierField.text = ""
            self.state = .enterIdentifier
        })
        alert.addCancel(title: "Try again")
        self.present(alert, animated: true)
    }
}
