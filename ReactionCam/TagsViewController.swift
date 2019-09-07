import Foundation
import TagListView
import UIKit

class TagsViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var tagListView: TagListView!
    @IBOutlet weak var tagField: UITextField!

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tagField.delegate = self
        self.tagField.setPlaceholder(text: "e.g. #hiphop 🔍", color: .darkGray)

        self.tagListView.alignment = .center
        self.tagListView.textFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let currentTags = SettingsManager.followedTags.map { "#\($0)" }
        self.tagListView.addTags(currentTags).forEach {
            $0.isSelected = true
        }
        self.tagListView.addTags(
            self.tags.filter { !currentTags.contains($0) }
        )
        self.tagListView.tagViews.forEach { tagView in
            tagView.onTap = self.tagTapHandler
        }
    }

    @IBAction func closeTapped(_ sender: Any) {
        guard !self.tagField.isFirstResponder || self.textFieldShouldReturn(self.tagField) else {
            return
        }

        SettingsManager.followedTags = self.tagListView.selectedTags().compactMap {
            guard let tag = $0.title(for: .normal) else {
                return nil
            }
            return self.stripHashtag(tag)
        }
        Logging.info("Updated Followed Tags", [
            "Tags": SettingsManager.followedTags.sorted().joined(separator: ","),
        ])

        if self.presentingViewController is LandingViewController {
            AppDelegate.requestNotificationPermissions(presentAlertWith: self, source: "Landing") { success in
                DispatchQueue.main.async {
                    let rootNavigation = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "RootNavigation")
                    self.present(rootNavigation, animated: true)
                }
            }
        } else {
            self.dismiss(animated: true)
        }
    }

    // MARK: UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        guard var tag = textField.text, !tag.isEmpty else {
            return true
        }
        Logging.log("Tag Searched", ["Tag": tag])
        tag = self.stripHashtag(tag)
        tag = tag.replacingOccurrences(of: " ", with: "").lowercased()
        guard tag.matches(of: "^[a-z0-9]{1,20}$").count == 1 else {
            let alert = UIAlertController(
                title: "Can‘t use hashtag",
                message: "Hashtags can only have letters and numbers.",
                preferredStyle: .alert)
            alert.addCancel(title: "OK")
            self.present(alert, animated: true)
            return false
        }
        textField.text = ""
        let hashtag = "#\(tag)"
        let tagView =
            self.tagListView.tagViews.first(where: { $0.title(for: .normal) == hashtag }) ??
            self.tagListView.insertTag(hashtag, at: 0)
        tagView.isSelected = true
        tagView.onTap = self.tagTapHandler
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) {
            $0.invalidate()
            tagView.pulse()
        }
        return true
    }

    private let tags = [
        "#hiphop",
        "#rap",
        "#musicvideo",
        "#music",
        "#movies",
        "#funny",
        "#worldstarhiphop",
        "#xxl",
        "#vlog",
        "#trynottorap",
        "#trynottosing",
        "#trynottolaugh",
        "#americasgottalent",
        "#challenge",
        "#fails",
        "#prank",
        "#scary"
    ]

    private var tagTapHandler: ((TagView) -> ()) {
        let handler: (TagView) -> () = { tagView in
            tagView.pulse()
            let selected = !tagView.isSelected
            tagView.isSelected = selected
            Logging.debug(selected ? "Tag Selected" : "Tag Deselected", [
                "Tag": tagView.title(for: .normal).flatMap(self.stripHashtag) ?? "N/A",
            ])
        }
        return handler
    }

    private func stripHashtag(_ text: String) -> String {
        return text.trimmingCharacters(in: ["#"])
    }
}
