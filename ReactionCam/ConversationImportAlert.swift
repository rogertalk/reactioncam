import FBSDKShareKit
import MessageUI
import UIKit
import XLActionController

protocol ConversationImportDelegate: class {
    var conversationImportAnchorView: UIView { get }
}

class ConversationImportAlert: NSObject, MFMessageComposeViewControllerDelegate {
    enum ImportAction { case invite }

    init(title: String?, message: String?, source: String, importActions: [ImportAction], owner: UIViewController, delegate: ConversationImportDelegate) {
        self.owner = owner
        self.delegate = delegate
        self.importActions = importActions
        self.title = title
        self.message = message
        self.source = source
        super.init()
    }

    func show() {
        let sheet = ActionSheetController(title: self.title)
        self.importActions.forEach {
            switch $0 {
            case .invite:
                sheet.addAction(Action("Start a chat 😎", style: .default) { _ in
                    let alert = UIAlertController(title: "Start Chat 👫", message: "Enter a username to start a direct message conversation with that user.", preferredStyle: .alert)
                    alert.addTextField(configurationHandler: { textField in
                        textField.keyboardAppearance = .dark
                        textField.keyboardType = .default
                        textField.placeholder = "username"
                        textField.returnKeyType = .done
                    })
                    alert.addAction(UIAlertAction(title: "Start chat", style: .default) { _ in
                        guard let username = alert.textFields?.first?.text?.trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                            let messages = Bundle.main.loadNibNamed("MessagesViewController", owner: nil, options: nil)?.first as? MessagesViewController else {
                                return
                        }
                        MessageService.instance.createThread(identifier: username) { thread, error in
                            guard let thread = thread, error == nil else {
                                let alert = UIAlertController(title: "Oops!", message: "An error occured while starting this chat. Please check the username and try again.", preferredStyle: .alert)
                                alert.addCancel(title: "OK")
                                self.owner?.present(alert, animated: true)
                                return
                            }
                            messages.thread = thread
                            self.owner?.navigationController?.pushViewController(messages, animated: true)
                        }
                    })
                    alert.addCancel()
                    self.owner?.present(alert, animated: true)
                })
                sheet.addAction(Action("Get Subscribers", style: .default) { _ in
                    Logging.success("Conversation Import Action", [
                        "Action": "Facebook",
                        "Source": self.source])
                    guard let vc = Bundle.main.loadNibNamed("SuggestedUsersViewController", owner: nil, options: nil)?.first as? SuggestedUsersViewController else {
                        return
                    }
                    self.owner?.navigationController?.pushViewController(vc, animated: true)
                })
                sheet.addAction(Action("Invite a Friend", style: .default) { _ in
                    Logging.success("Conversation Import Action", [
                        "Action": "Invite a Friend",
                        "Source": self.source])
                    let body = SettingsManager.shareChannelCopy(account: BackendClient.api.session)
                    let vc = UIActivityViewController(activityItems: [DynamicActivityItem(body)], applicationActivities: nil)
                    vc.excludedActivityTypes = SettingsManager.shareLinkExcludedActivityTypes
                    self.present(sheet: vc)
                })
                if let session = BackendClient.api.session {
                    sheet.addAction(Action("My Subscriptions", style: .default) { _ in
                        Logging.success("Conversation Import Action", [
                            "Action": "My Subscriptions",
                            "Source": self.source])
                        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "AccountList") as! AccountListViewController
                        vc.type = .following(account: session)
                        self.owner?.navigationController?.pushViewController(vc, animated: true)
                    })
                }
            }
        }
        sheet.addCancel() {
            Logging.log("Conversation Import Action", ["Action": "Cancel"])
        }
        self.present(sheet: sheet)
    }

    // MARK: - MFMessageComposeViewControllerDelegate

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }

    // MARK: - Private

    private let importActions: [ImportAction]
    private let message: String?
    private let source: String
    private let title: String?

    private weak var delegate: ConversationImportDelegate?
    private weak var owner: UIViewController?

    private func present(sheet: UIViewController) {
        if let delegate = self.delegate {
            sheet.configurePopover(sourceView: delegate.conversationImportAnchorView)
        }
        self.owner?.present(sheet, animated: true)
    }
}
