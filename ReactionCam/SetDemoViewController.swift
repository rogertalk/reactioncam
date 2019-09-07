import UIKit

class SetDemoViewController : UIViewController {

    static var shouldAskLater = false

    @IBOutlet weak var agePicker: UIDatePicker!
    @IBOutlet weak var femaleToggle: ToggleButton!
    @IBOutlet weak var maleToggle: ToggleButton!
    @IBOutlet weak var otherToggle: ToggleButton!
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.statusIndicatorView = StatusIndicatorView.create(container: self.view)
        
        self.agePicker.backgroundColor = .black
        self.agePicker.setValue(UIColor.white, forKey: "textColor")
        self.agePicker.date = Date(timeIntervalSince1970: 852076800)
        self.agePicker.maximumDate = Date()
    }
    
    @IBAction func genderToggleTapped(_ sender: ToggleButton) {
        guard !sender.isOn else {
            return
        }
        switch sender {
        case self.maleToggle:
            self.femaleToggle.isOn = false
            self.otherToggle.isOn = false
        case self.femaleToggle:
            self.maleToggle.isOn = false
            self.otherToggle.isOn = false
        default:
            self.maleToggle.isOn = false
            self.femaleToggle.isOn = false
        }
    }
    
    @IBAction func confirmTapped(_ sender: Any) {
        let birthdate = self.agePicker.date
        guard birthdate.timeIntervalSinceNow < -409968000 else {
            Logging.warning("User Demographics Alert", ["Alert": "MustBe13", "EnteredDate": birthdate.description])
            let alert = UIAlertController(title: "Oops!", message: "Sorry, you must be at least 13 years old to use Reaction.cam, but thanks for checking us out!", preferredStyle: .alert)
            alert.addCancel(title: "Got it")
            self.present(alert, animated: true)
            return
        }
        guard let gender: Intent.Gender = self.maleToggle.isOn ? .male :
            self.femaleToggle.isOn ? .female :
            self.otherToggle.isOn ? .other : nil else {
                Logging.warning("User Demographics Alert", ["Alert": "MustPickGender"])
                let alert = UIAlertController(title: "Oops!", message: "Please specify your gender.", preferredStyle: .alert)
                alert.addCancel(title: "OK")
                self.present(alert, animated: true)
                return
        }

        self.statusIndicatorView.showLoading()
        Intent.updateProfileDemographics(birthday: birthdate, gender: gender).perform(BackendClient.api) { _ in
            self.statusIndicatorView.hide()
            self.dismiss(animated: true)
        }
    }
    
    @IBAction func laterTapped(_ sender: Any) {
        SetDemoViewController.shouldAskLater = true
        self.dismiss(animated: true)
    }
    
    private var statusIndicatorView: StatusIndicatorView!
}
