import Foundation
import UIKit

class EditRewardsViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
    
    @IBOutlet weak var scrollView: UIScrollView!
    
    @IBOutlet weak var firstTierAmountField: PaddedTextField!
    @IBOutlet weak var firstTierRewardField: UITextView!
    @IBOutlet weak var firstTierTitleField: PaddedTextField!
    @IBOutlet weak var secondTierAmountField: PaddedTextField!
    @IBOutlet weak var secondTierRewardField: UITextView!
    @IBOutlet weak var secondTierTitleField: PaddedTextField!
    @IBOutlet weak var thirdTierAmountField: PaddedTextField!
    @IBOutlet weak var thirdTierRewardField: UITextView!
    @IBOutlet weak var thirdTierTitleField: PaddedTextField!

    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(EditRewardsViewController.handleTap)))

        self.scrollView.keyboardDismissMode = .onDrag
        self.scrollView.showsVerticalScrollIndicator = true
        self.scrollView.indicatorStyle = .white

        self.firstTierRewardField.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        self.secondTierRewardField.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        self.thirdTierRewardField.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        // TODO: Make tiers into a tableview and iterate over tiers data in session to add and populate cells.
        self.firstTierAmountField.delegate = self
        self.firstTierRewardField.delegate = self
        self.firstTierTitleField.delegate = self
        self.secondTierAmountField.delegate = self
        self.secondTierRewardField.delegate = self
        self.secondTierTitleField.delegate = self
        self.thirdTierAmountField.delegate = self
        self.thirdTierRewardField.delegate = self
        self.thirdTierTitleField.delegate = self

        if let tiers = BackendClient.api.session?.properties["tiers"] as? [[String: Any]] {
            guard tiers.count > 0 else {
                return
            }
            let first = tiers[0]
            self.firstTierAmountField.text = String(first["coins"] as? Int ?? 0)
            self.firstTierTitleField.text = first["title"] as? String ?? ""
            self.firstTierRewardField.text = first["description"] as? String ?? ""
            
            guard tiers.count > 1 else {
                return
            }
            let second = tiers[1]
            self.secondTierAmountField.text = String(second["coins"] as? Int ?? 0)
            self.secondTierTitleField.text = second["title"] as? String ?? ""
            self.secondTierRewardField.text = second["description"] as? String ?? ""
            
            guard tiers.count > 2 else {
                return
            }
            let third = tiers[2]
            self.thirdTierAmountField.text = String(third["coins"] as? Int ?? 0)
            self.thirdTierTitleField.text = third["title"] as? String ?? ""
            self.thirdTierRewardField.text = third["description"] as? String ?? ""
        }
    }
        
    override func viewWillDisappear(_ animated: Bool) {
        self.view.endEditing(true)
        super.viewWillDisappear(true)
    }

    // MARK: - Actions
    
    @IBAction func closeTapped(_ sender: Any) {
        self.dismiss(animated: true)
    }

    @IBAction func learnMoreTapped(_ sender: Any) {
        Logging.log("Edit Rewards", ["Action": "Learn More"])
        UIApplication.shared.open(SettingsManager.helpCoinsURL, options: [:])
    }

    @IBAction func saveTapped(_ sender: Any) {
        guard let tiers = self.getTiers() else {
            let alert = UIAlertController(title: "Invalid Reward Tier", message: "Reward tiers must have coin amounts greater than zero, a title, and a description. To remove the reward tier, leave the coin amount empty.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return
        }
        Intent.updateProfileProperties(properties: ["tiers": tiers]).perform(BackendClient.api) {
            guard $0.successful else {
                let alert = UIAlertController(
                    title: "Uh oh!",
                    message: "Something went wrong, please try again later.",
                    preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
            }
            self.dismiss(animated: true)
        }
    }
    
    // MARK: UITextFieldDelegate
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        let offset: CGFloat
        switch textField {
        case self.firstTierAmountField, self.secondTierAmountField, self.thirdTierAmountField:
            offset = textField.convert(textField.frame, to: self.scrollView).origin.y
        default:
            offset = textField.frame.origin.y
        }
        self.scrollView.setContentOffset(CGPoint(x: 0, y: offset - 64), animated: true)
    }
    
    // MARK: UITextViewDelegate
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        self.scrollView.setContentOffset(CGPoint(x: 0, y: textView.frame.origin.y - 86), animated: true)
    }
    
    // MARK: Private

    private func getTiers() -> [[String: Any]]? {
        var tiers = [[String: Any]]()
        if let amount = self.firstTierAmountField.text, !amount.isEmpty {
            guard let title = self.firstTierTitleField.text,
                let reward = self.firstTierRewardField.text,
                let tier = self.parseTier(amount: amount, title: title, description: reward) else {
                    return nil
            }
            tiers.append(tier)
        }
        if let amount = self.secondTierAmountField.text, !amount.isEmpty {
            guard let title = self.secondTierTitleField.text,
                let reward = self.secondTierRewardField.text,
                let tier = self.parseTier(amount: amount, title: title, description: reward) else {
                    return nil
            }
            tiers.append(tier)
        }
        if let amount = self.thirdTierAmountField.text, !amount.isEmpty {
            guard let title = self.thirdTierTitleField.text,
                let reward = self.thirdTierRewardField.text,
                let tier = self.parseTier(amount: amount, title: title, description: reward) else {
                    return nil
            }
            tiers.append(tier)
        }
        return tiers
    }
    
    @objc private dynamic func handleTap() {
        self.view.endEditing(true)
    }

    private func parseTier(amount: String, title: String, description: String) -> [String: Any]? {
        guard let coins = amount.intValue,
            coins != 0 else {
                return nil
        }
        let title = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !title.isEmpty && !description.isEmpty else {
            return nil
        }
        return ["coins": coins, "title": title, "description": description]
    }
}
