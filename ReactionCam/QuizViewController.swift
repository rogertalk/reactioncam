import UIKit

class QuizViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var keyboardHeight: NSLayoutConstraint!
    @IBOutlet weak var optionAButton: UIButton!
    @IBOutlet weak var optionBButton: UIButton!
    @IBOutlet weak var optionCButton: UIButton!
    @IBOutlet weak var customTextField: PaddedTextField!

    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.customTextField.delegate = self

        self.optionAButton.setHeavyShadow()
        self.optionBButton.setHeavyShadow()
        self.optionCButton.setHeavyShadow()
        self.customTextField.setHeavyShadow()
        self.continueButton.isHidden = true

        self.optionAButton.setTitle("Subscribers", for: .normal)
        self.optionBButton.setTitle("Squad", for: .normal)
        self.optionCButton.setTitle("Fam", for: .normal)
        self.customTextField.placeholder = "custom"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(QuizViewController.keyboardEvent), name: .UIKeyboardWillChangeFrame, object: nil)
    }

    // MARK: - Actions

    @IBAction func continueTapped(_ sender: UIButton) {
        Logging.log("Quiz View Controller", ["Action": "Continue Tapped", "Choice": self.answer ?? "", "Custom": self.selectedOption == self.customTextField])
        sender.isEnabled = false
        sender.setTitle("Hold on... 😄", for: .disabled)
        let props = ["followers_title": self.answer as Any]
        Intent.updateProfileProperties(properties: props).perform(BackendClient.api) {
            guard $0.successful else {
                let message: String
                switch $0.code {
                case 400:
                    message = "That name is not valid. Try another one!"
                default:
                    message = "Something went wrong. Please check your connection and try again."
                }
                let alert = UIAlertController(title: "Oops!", message: message, preferredStyle: .alert)
                alert.addCancel(title: "OK") {
                    self.dismiss(animated: true)
                }
                self.present(alert, animated: true)
                sender.isEnabled = true
                return
            }
            self.dismiss(animated: true)
        }
    }

    @IBAction func optionTapped(_ sender: UIButton) {
        Logging.log("Quiz View Controller", ["Action": "Option Tapped", "Value": sender.titleLabel?.text ?? ""])
        guard let value = sender.titleLabel?.text, !value.isEmpty else {
            return
        }
        self.customTextField.resignFirstResponder()
        self.optionAButton.backgroundColor = .white
        self.optionBButton.backgroundColor = .white
        self.optionCButton.backgroundColor = .white
        self.customTextField.backgroundColor = .white
        sender.backgroundColor = .uiYellow
        sender.pulse()
        self.selectedOption = sender
        self.answer = value
    }

    // MARK: UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text else {
            return true
        }
        let newLength = text.count + string.count - range.length
        return newLength <= SettingsManager.followersTitleMaxLength
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        Logging.log("Quiz View Controller", ["Action": "Custom Option Tapped", "Value": textField.text ?? ""])
        self.optionAButton.backgroundColor = .white
        self.optionBButton.backgroundColor = .white
        self.optionCButton.backgroundColor = .white
        textField.pulse()
        textField.backgroundColor = .uiYellow
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        Logging.log("Quiz View Controller", ["Action": "Custom Option Typed", "Value": textField.text ?? ""])
        guard let value = textField.text, !value.isEmpty else {
            textField.backgroundColor = .white
            self.answer = nil
            return
        }
        self.selectedOption = textField
        self.answer = value
    }
    
    // MARK: - Private

    private var answer: String? {
        didSet {
            guard let answer = self.answer, !answer.isEmpty else {
                self.continueButton.isHidden = true
                return
            }
            self.continueButton.isHidden = false
        }
    }

    private var selectedOption: UIView?

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
}
