import UIKit

/// A list of activity types that will only accept a URL.
fileprivate let linkOnlyActivityTypes = [
    UIActivityType.postToFacebook,
    UIActivityType.copyToPasteboard,
    UIActivityType(rawValue: "com.facebook.Messenger.ShareExtension"),
    UIActivityType(rawValue: "com.kik.chat.share-extension"),
    UIActivityType(rawValue: "com.skype.skype.sharingextension"),
    UIActivityType(rawValue: "com.tencent.xin.sharetimeline"),
    UIActivityType(rawValue: "com.toyopagroup.picaboo.share"),
    UIActivityType(rawValue: "ph.telegra.Telegraph.Share"),
]
fileprivate let linkRegex = try! NSRegularExpression(pattern: "https://www.reaction.cam[^ ]*", options: [])

/// Takes a fallback value to be shared and a map values for specific activity types.
class DynamicActivityItem: NSObject, UIActivityItemSource {
    let activityTypeToValue: [UIActivityType: Any]
    let fallback: Any

    init(_ fallback: Any, specific: [UIActivityType: Any] = [:]) {
        self.activityTypeToValue = specific
        self.fallback = fallback
    }

    @objc func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return self.fallback
    }

    @objc func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivityType?) -> String {
        // This data type gets us the most possible share destinations.
        return "public.url"
    }

    @objc func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivityType?) -> Any? {
        guard let type = activityType else { return self.fallback }
        if let value = self.activityTypeToValue[type] {
            return value
        }
        guard
            linkOnlyActivityTypes.contains(type),
            let text = self.fallback as? NSString,
            let match = linkRegex.matches(in: text as String, options: [], range: NSMakeRange(0, text.length)).first,
            let url = URL(string: text.substring(with: match.range))
            else { return self.fallback }
        return url
    }
}

