import FBSDKLoginKit
import UIKit

class EditProfileViewController: UIViewController,
    UITextFieldDelegate,
    UITextViewDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate {

    enum EditProfileAction {
        case none, updatePicture
    }

    var action: EditProfileAction = .none

    @IBOutlet weak var avatarView: UIImageView!
    @IBOutlet weak var bioTextView: UITextView!
    @IBOutlet weak var emailButton: UIButton!
    @IBOutlet weak var emailButtonLabel: UILabel!
    @IBOutlet weak var followersTitleTextField: PaddedTextField!
    @IBOutlet weak var instagramField: UITextField!
    @IBOutlet weak var itemChangePasswordView: UIView!
    @IBOutlet weak var itemConnectFacebookView: UIView!
    @IBOutlet weak var itemFacebookView: UIView!
    @IBOutlet weak var itemWebsiteView: UIView!
    @IBOutlet weak var itemYouTubeView: UIView!
    @IBOutlet weak var itemInstagramView: UIView!
    @IBOutlet weak var itemSnapchatView: UIView!
    @IBOutlet weak var itemTwitterView: UIView!
    @IBOutlet weak var itemVerifiedView: UIView!
    @IBOutlet weak var itemVideoQualityView: UIView!
    @IBOutlet weak var itemWatermarkView: UIView!
    @IBOutlet weak var linkButton: UIButton!
    @IBOutlet weak var facebookField: PaddedTextField!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var snapchatField: UITextField!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var twitterField: UITextField!
    @IBOutlet weak var urlField: PaddedTextField!
    @IBOutlet weak var verifiedSwitch: UISwitch!
    @IBOutlet weak var videoQualitySwitch: UISwitch!
    @IBOutlet weak var watermarkSwitch: UISwitch!
    @IBOutlet weak var youTubeField: UITextField!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)

        self.scrollView.keyboardDismissMode = .onDrag
        self.scrollView.showsVerticalScrollIndicator = true
        self.scrollView.indicatorStyle = .white

        self.imagePicker.allowsEditing = true
        self.imagePicker.delegate = self

        self.instagramField.delegate = self
        self.urlField.delegate = self
        self.nameTextField.delegate = self
        self.facebookField.delegate = self
        self.youTubeField.delegate = self
        self.snapchatField.delegate = self
        self.twitterField.delegate = self
        self.bioTextView.delegate = self
        self.followersTitleTextField.delegate = self

        self.bioTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        self.avatarView.layer.borderColor = UIColor.uiYellow.cgColor
        self.avatarView.layer.borderWidth = 3
        if let url = BackendClient.api.session?.imageURL {
            // Prefill image if this is an existing account.
            self.avatarView.af_setImage(withURL: url)
        }
        self.avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.handleAvatarTapped)))

        guard let session = BackendClient.api.session else {
            return
        }
        // Prefill data
        if session.hasBeenOnboarded {
            self.nameTextField.text = session.username
        } else {
            self.nameTextField.placeholder = session.username
        }
        self.linkButton.setTitle("🔗 \(SettingsManager.getChannelURL(username: session.username).replacingOccurrences(of: "https://", with: ""))", for: .normal)
        self.urlField.text = session.properties["url"] as? String
        self.facebookField.text = session.properties["facebook"] as? String
        self.instagramField.text = session.properties["instagram"] as? String
        self.snapchatField.text = session.properties["snapchat"] as? String
        self.twitterField.text = session.properties["twitter"] as? String
        self.youTubeField.text = session.properties["youtube"] as? String
        self.bioTextView.text = session.properties["bio"] as? String ?? SettingsManager.defaultBio
        self.followersTitleTextField.text = session.properties["followers_title"] as? String
        self.watermark = session.properties["watermark"] as? String
        if self.watermark != nil {
            self.watermarkSwitch.isOn = true
        }
        self.verifiedSwitch.isOn = session.isVerified

        self.itemFacebookView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemFacebookTapped)))
        self.itemInstagramView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemInstagramTapped)))
        self.itemSnapchatView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemSnapchatTapped)))
        self.itemTwitterView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemTwitterTapped)))
        self.itemVerifiedView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemVerifiedTapped)))
        self.itemVideoQualityView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemVideoQualityTapped)))
        self.itemWatermarkView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemWatermarkTapped)))

        self.itemWebsiteView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemWebsiteTapped)))
        self.itemYouTubeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditProfileViewController.itemYouTubeTapped)))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let email = BackendClient.api.session?.email {
            self.emailButton.isUserInteractionEnabled = false
            self.emailButton.setTitle(email, for: .normal)
            self.emailButtonLabel.text = "🔒"
            self.emailButtonLabel.font = UIFont.systemFont(ofSize: 26.0)
        } else {
            self.emailButton.isUserInteractionEnabled = true
            self.emailButton.setTitle("Verify Email", for: .normal)
        }
        self.videoQualitySwitch.isOn = SettingsManager.recordQuality == .high
        self.itemConnectFacebookView.isHidden = FBSDKAccessToken.current() != nil
        self.itemChangePasswordView.isHidden = !(BackendClient.api.session?.hasBeenOnboarded ?? false)
        SettingsManager.editProfileShown = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        switch self.action {
        case .updatePicture:
            self.present(self.imagePicker, animated: true)
            self.action = .none
        default:
            if !(BackendClient.api.session?.hasBeenOnboarded ?? false) {
                self.nameTextField.becomeFirstResponder()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
    }

    // MARK: - Actions

    @IBAction func changePasswordTapped(_ sender: Any) {
        Logging.log("Edit Profile Action", ["Action": "Change Password"])
        self.showSetPassword(update: true)
    }

    @IBAction func closeTapped(_ sender: Any) {
        Logging.log("Edit Profile Action", ["Action": "Cancel"])
        self.dismiss(animated: true)
    }

    @IBAction func confirmTapped(_ sender: AnyObject) {
        Logging.log("Edit Profile Action", ["Action": "Save"])
        guard let username = self.nameTextField.text, !username.isEmpty else {
            Logging.warning("Edit Profile Error", ["Error": "Missing Username"])
            self.showAlert(
                "Uh oh!",
                message: "That doesn't look like your username.",
                cancelTitle: "Try again",
                tappedActionCallback: { _ in
                    self.nameTextField.becomeFirstResponder()
                })
            return
        }
        let signUp = !(BackendClient.api.session?.hasBeenOnboarded ?? false)
        var url = self.urlField.text!
        if !url.isEmpty {
            guard let urlString = URL(string: url)?.absoluteString, urlString.hasPrefix("http://") || urlString.hasPrefix("https://") else {
                self.showAlert(
                    "Uh oh!",
                    message: "Make sure to copy and paste the right LINK.\n\nEg: http://example.com/your_page",
                    cancelTitle: "Try again",
                    tappedActionCallback: { _ in
                        self.urlField.becomeFirstResponder()
                    })
                return
            }
            url = urlString
        }

        self.statusIndicatorView.showLoading()

        var image: Intent.Image? = nil
        if let data = self.userPhotoData {
            image = .jpeg(data)
        }
        let props = [
            "url": url as Any,
            "facebook": self.facebookField.text as Any,
            "youtube": self.youTubeField.text as Any,
            "snapchat": self.snapchatField.text as Any,
            "twitter": self.twitterField.text as Any,
            "instagram": self.instagramField.text as Any,
            "bio": self.bioTextView.text as Any,
            "followers_title": self.followersTitleTextField.text as Any,
            "watermark": self.watermark as Any,
        ]
        Intent.updateProfile(username: username, image: image, properties: props).perform(BackendClient.api) {
            self.statusIndicatorView.hide()
            guard $0.successful else {
                Logging.warning("Edit Profile Error", ["Error": $0.code == 409 ? "Username Taken" : "Unknown\($0.code)"])
                let message: String
                if $0.code == 409 {
                    message = "That username is already taken. Please try again with a different one."
                } else {
                    message = "Something went wrong. Please try again."
                }
                self.showAlert("Uh oh!", message: message, cancelTitle: "OK")
                return
            }
            if signUp {
                self.showSetPassword(update: false) {
                    self.dismiss(animated: true)
                }
            } else {
                self.dismiss(animated: true)
            }
        }
        SettingsManager.recordQuality = self.videoQualitySwitch.isOn ? .high : .medium
    }

    @IBAction func connectFacebookTapped(_ sender: Any) {
        Logging.log("Edit Profile Action", ["Action": "Connect Facebook"])
        self.statusIndicatorView.showLoading()
        AppDelegate.connectFacebook(presenter: self) { success in
            self.statusIndicatorView.hide()
            Logging.log("Edit Profile Action", ["Action": "ConnectFacebook", "Result": success])
        }
    }

    @IBAction func emailTapped(_ sender: Any) {
        let challenge = self.storyboard?.instantiateViewController(withIdentifier: "Challenge") as! ChallengeViewController
        challenge.mode = .connectEmail
        self.present(challenge, animated: true)
    }
    
    @objc private dynamic func handleAvatarTapped() {
        self.present(self.imagePicker, animated: true)
    }

    @IBAction func helpTapped(_ sender: Any) {
        Logging.log("Edit Profile Action", ["Action": "Learn More"])
        UIApplication.shared.open(SettingsManager.helpReactToSocialURL, options: [:])
    }

    @IBAction func linkTapped(_ sender: Any) {
        Logging.log("Edit Profile Action", ["Action": "Copy Link"])
        if let username = self.nameTextField.text, !username.isEmpty {
            UIPasteboard.general.string = SettingsManager.getChannelURL(username: username)
        } else if let username = BackendClient.api.session?.username {
            UIPasteboard.general.string = SettingsManager.getChannelURL(username: username)
        } else {
            return
        }
        self.statusIndicatorView.showConfirmation(title: "Link Copied")
    }

    @IBAction func logOutTapped(_ sender: Any) {
        Logging.log("Edit Profile Action", ["Action": "Log Out"])
        var message: String?
        if BackendClient.api.session?.email != nil {
            message = nil
        } else {
            message = "WARNING: You will not be able to recover your account unless you verify your email."
        }
        let alert = UIAlertController(title: "Are you sure?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Yes, log out", style: .destructive) { _ in
            Intent.logOut().perform(BackendClient.api)
            Logging.log("Edit Profile Action", ["Action": "Log Out Yes"])
        })
        alert.addCancel()
        self.present(alert, animated: true)
    }

    @IBAction func usernameEditingChanged(_ sender: Any) {
        UIView.performWithoutAnimation {
            self.linkButton.setTitle("🔗 \(SettingsManager.getChannelURL(username: self.nameTextField.text!).replacingOccurrences(of: "https://", with: ""))", for: .normal)
            self.linkButton.layoutIfNeeded()
        }
    }

    @IBAction func videoQualityToggled(_ sender: UISwitch) {
        guard let account = BackendClient.api.session else {
            return
        }

        guard sender.isOn else {
            Logging.debug("Edit Profile Action", ["Action": "Video Quality Toggle", "Result": false, "Follower Count": account.followerCount])
            return
        }

        if account.followerCount < 100 {
            Logging.debug("Edit Profile Action", ["Action": "Video Quality Toggle", "Result": false, "Follower Count": account.followerCount])
            let alert = UIAlertController(
                title: "You need at least 100 subscribers to enable 1080p! ✨",
                message: "Protip: Subscribe to your favorite creators and they may subscribe to you back!",
                preferredStyle: .alert)
            alert.addCancel(title: "OK") {
                sender.isOn = false
            }
            self.present(alert, animated: true)
        }
    }

    @IBAction func watermarkToggled(_ sender: UISwitch) {
        Logging.debug("Edit Profile Action", ["Action": "Custom Watermark Toggle", "Result": sender.isOn])
        guard sender.isOn else {
            let alert = UIAlertController(title: "\"\(self.watermark ?? "")\"", message: "Do you want to delete this custom watermark?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                self.watermark = nil
                sender.isOn = false
                Logging.debug("Edit Profile Action", ["Action": "Custom Watermark Deleted"])
            })
            alert.addCancel() {
                sender.isOn = true
            }
            self.present(alert, animated: true)
            return
        }

        let alert = UIAlertController(title: "Custom Watermark", message: "Pick the watermark you want on the future videos you create.", preferredStyle: .alert)
        weak var textField: UITextField?
        alert.addTextField {
            textField = $0
            $0.keyboardAppearance = .dark
            $0.keyboardType = .default
            $0.isSecureTextEntry = false
            $0.placeholder = BackendClient.api.session?.hasBeenOnboarded ?? false ? "@\(BackendClient.api.session!.username)" : ""
            $0.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in
            guard let text = textField?.text, text.count <= SettingsManager.watermarkMaxLength else {
                let error = UIAlertController(title: "Oops!", message: "Watermark needs to be 30 characters or less.", preferredStyle: .alert)
                error.addCancel(title: "OK") {
                    self.present(alert, animated: true)
                }
                self.present(error, animated: true)
                return
            }
            self.watermark = text
            Logging.debug("Edit Profile Action", ["Action": "Custom Watermark Set", "Result": text])
        })
        alert.addCancel() {
            self.watermark = nil
            sender.isOn = false
            return
        }
        self.present(alert, animated: true)
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        defer {
            picker.dismiss(animated: true)
        }

        guard
            let image = info[UIImagePickerControllerEditedImage] as? UIImage,
            let imageData = UIImageJPEGRepresentation(image, 0.8)
            else
        {
            Logging.log("Profile Image Picker", ["Result": "Cancel"])
            return
        }

        self.userPhotoData = imageData
        self.avatarView.image = image

        Logging.log("Profile Image Picker", ["Result": "PickedImage"])
    }

    // MARK: UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField == self.nameTextField,
            range.location == 0,
            !(string.first?.isLetter ?? true) {
            let alert = UIAlertController(title: "Oops! 😅", message: "Usernames must start with a letter.", preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
            return false
        }

        guard let text = textField.text else {
            return true
        }
        if textField == self.followersTitleTextField {
            let newLength = text.count + string.count - range.length
            return newLength <= SettingsManager.followersTitleMaxLength
        } else {
            return true
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        let offset = textField.superview?.superview == self.scrollView ? textField.frame.origin.y - 32 : (textField.superview?.frame.origin.y ?? 0) - 32
        self.scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: true)
    }

    // MARK: UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        self.scrollView.setContentOffset(CGPoint(x: 0, y: textView.frame.origin.y - 32), animated: true)
    }

    // MARK: Private

    private let imagePicker = UIImagePickerController()
    private var statusIndicatorView: StatusIndicatorView!
    private var userPhotoData: Data?
    private var watermark: String?

    private func showAlert(_ title: String, message: String, cancelTitle: String, actionTitle: String? = nil, tappedActionCallback: ((Bool) -> ())? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let action = actionTitle {
            let positiveAction = UIAlertAction(title: action, style: .default) { action in
                tappedActionCallback?(true) }
            alert.addAction(positiveAction)
            alert.preferredAction = positiveAction
        }
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { action in tappedActionCallback?(false) })
        self.present(alert, animated: true)
    }

    private func showSetPassword(update: Bool = false, callback: (() -> ())? = nil) {
        var title: String?
        var message: String?
        if update {
            title = "Change Password"
            message = "If you never set a password before, leave \"Current password\" empty."
        } else {
            title = "Set Password"
            message = nil
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        weak var currentField, passwordField, confirmField: UITextField?
        if update {
            alert.addTextField {
                currentField = $0
                $0.keyboardAppearance = .dark
                $0.keyboardType = .default
                $0.isSecureTextEntry = true
                $0.placeholder = "Current password"
                $0.returnKeyType = .done
            }
        }
        alert.addTextField {
            passwordField = $0
            $0.keyboardAppearance = .dark
            $0.keyboardType = .default
            $0.isSecureTextEntry = true
            $0.placeholder = "New password"
            $0.returnKeyType = .done
        }
        alert.addTextField {
            confirmField = $0
            $0.keyboardAppearance = .dark
            $0.keyboardType = .default
            $0.isSecureTextEntry = true
            $0.placeholder = "Confirm new password"
            $0.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in
            guard
                let new = passwordField?.text, !new.isEmpty,
                let confirm = confirmField?.text, !confirm.isEmpty
            else {
                let error = UIAlertController(title: "Oops!", message: "Fill out the password fields.", preferredStyle: .alert)
                error.addCancel(title: "OK") {
                    self.present(alert, animated: true)
                }
                self.present(error, animated: true)
                return

            }
            guard new == confirm else {
                let error = UIAlertController(title: "Oops!", message: "New passwords do not match. Please try again.", preferredStyle: .alert)
                error.addCancel(title: "OK") {
                    self.present(alert, animated: true)
                }
                self.present(error, animated: true)
                return
            }
            self.statusIndicatorView.showLoading()
            Intent.changePassword(newPassword: new, oldPassword: currentField?.text ?? "").perform(BackendClient.api) {
                guard $0.successful else {
                    self.statusIndicatorView.hide()
                    let error = UIAlertController(
                        title: "Uh oh",
                        message: "Failed to change password. Make sure your password is correct and try again.",
                        preferredStyle: .alert)
                    error.addCancel(title: "OK") {
                        self.present(alert, animated: true)
                    }
                    self.present(error, animated: true)
                    return
                }
                self.statusIndicatorView.showConfirmation()
                callback?()
            }
        })
        if update {
            alert.addCancel()
        }
        self.present(alert, animated: true)
    }

    @objc private dynamic func itemFacebookTapped() {
        self.facebookField.becomeFirstResponder()
    }

    @objc private dynamic func itemInstagramTapped() {
        self.instagramField.becomeFirstResponder()
    }

    @objc private dynamic func itemSnapchatTapped() {
        self.snapchatField.becomeFirstResponder()
    }

    @objc private dynamic func itemTwitterTapped() {
        self.twitterField.becomeFirstResponder()
    }

    @objc private dynamic func itemVerifiedTapped() {
        Logging.debug("Edit Profile Action", ["Action": "Verified Toggle", "Result": self.verifiedSwitch.isOn])
        guard !self.verifiedSwitch.isOn else {
            return
        }
        let alert = UIAlertController(
            title: "Sign up at:\n\nwww.reaction.cam/artists\n",
            message: nil,
            preferredStyle: .alert)
        alert.addCancel(title: "OK")
        self.present(alert, animated: true)
    }

    @objc private dynamic func itemVideoQualityTapped() {
        guard self.videoQualitySwitch.isEnabled else {
            return
        }
        self.videoQualitySwitch.setOn(!self.videoQualitySwitch.isOn, animated: true)
        self.videoQualityToggled(self.videoQualitySwitch)
    }

    @objc private dynamic func itemWatermarkTapped() {
        guard self.watermarkSwitch.isEnabled else {
            return
        }
        self.watermarkSwitch.setOn(!self.watermarkSwitch.isOn, animated: true)
        self.watermarkToggled(self.watermarkSwitch)
    }

    @objc private dynamic func itemWebsiteTapped() {
        self.urlField.becomeFirstResponder()
    }

    @objc private dynamic func itemYouTubeTapped() {
        self.youTubeField.becomeFirstResponder()
    }
}

