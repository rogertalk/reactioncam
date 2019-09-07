import AVFoundation
import UIKit

protocol PermissionsDelegate: class {
    func didReceivePermissions()
}

class PermissionsView: UIView {

    static var hasPermissions: Bool {
        return (
            AVCaptureDevice.authorizationStatus(for: .video) == .authorized &&
            (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized || TARGET_OS_SIMULATOR != 0)
        )
    }

    weak var delegate: PermissionsDelegate?

    @IBOutlet weak var enableCameraButton: HighlightButton!
    @IBOutlet weak var enableMicrophoneButton: HighlightButton!

    static func create(frame: CGRect, delegate: PermissionsDelegate) -> PermissionsView {
        let view = Bundle.main.loadNibNamed("PermissionsView", owner: self, options: nil)?[0] as! PermissionsView
        view.frame = frame
        view.delegate = delegate
        return view
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.refresh()
    }

    func refresh() {
        DispatchQueue.main.async {
            let camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized || (TARGET_OS_SIMULATOR != 0)
            self.enableCameraButton.isEnabled = !camera
            self.enableMicrophoneButton.isEnabled = !mic
            if camera && mic {
                self.delegate?.didReceivePermissions()
            }
        }
    }

    @IBAction func enableCameraTapped(_ sender: Any) {
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
            self.openPermissionSettings()
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                Logging.danger("Permission Denied", ["Permission": "Camera"])
                return
            }
            Logging.success("Permission Granted", ["Permission": "Camera"])
            self.refresh()
        }
    }

    @IBAction func enableMicrophoneTapped(_ sender: Any) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) != .denied else {
            self.openPermissionSettings()
            return
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            guard granted else {
                Logging.danger("Permission Denied", ["Permission": "Microphone"])
                return
            }
            Logging.success("Permission Granted", ["Permission": "Microphone"])
            self.refresh()
        }
    }

    private func openPermissionSettings() {
        AppDelegate.applicationActiveStateChanged.addListener(self, method: PermissionsView.handleApplicationActiveStateChanged)
        UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
    }

    private func handleApplicationActiveStateChanged(active: Bool) {
        guard active else {
            return
        }
        self.refresh()
        AppDelegate.applicationActiveStateChanged.removeListener(self)
    }
}
