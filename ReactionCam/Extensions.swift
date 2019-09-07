import Alamofire
import AlamofireImage
import AVFoundation
import CoreGraphics
import CoreVideo
import Darwin
import MessageUI

extension AVAsset {
    func generateThumbnail(at time: CMTime = CMTime(seconds: 0, preferredTimescale: 44100)) -> UIImage? {
        // If the thumbnail doesn't exist, generate it now.
        // No thumbnail for audio-only content.
        guard self.tracks(withMediaType: .video).first != nil else {
            return nil
        }
        let generator = AVAssetImageGenerator(asset: self)
        generator.maximumSize = CGSize(width: 640, height: 640)
        do {
            // Extract an image from the image generator.
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            NSLog("Failed to generate thumbnail: (\(error))")
        }
        return nil
    }
}

extension AVAudioSessionRouteChangeReason: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .categoryChange:
            return "categoryChange"
        case .newDeviceAvailable:
            return "newDeviceAvailable"
        case .noSuitableRouteForCategory:
            return "noSuitableRouteForCategory"
        case .oldDeviceUnavailable:
            return "oldDeviceUnavailable"
        case .override:
            return "override"
        case .routeConfigurationChange:
            return "routeConfigurationChange"
        case .unknown:
            return "unknown"
        case .wakeFromSleep:
            return "wakeFromSleep"
        }
    }
}

extension AVAudioSessionRouteDescription {
    var shortDescription: String {
        return "\(self.inputs.map({ $0.uid }).joined(separator: ", ")) + \(self.outputs.map({ $0.uid }).joined(separator: ", "))"
    }
}

extension AVCaptureSession.InterruptionReason: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .audioDeviceInUseByAnotherClient:
            return "audioDeviceInUseByAnotherClient"
        case .videoDeviceInUseByAnotherClient:
            return "videoDeviceInUseByAnotherClient"
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "videoDeviceNotAvailableDueToSystemPressure"
        case .videoDeviceNotAvailableInBackground:
            return "videoDeviceNotAvailableInBackground"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "videoDeviceNotAvailableWithMultipleForegroundApps"
        }
    }
}

extension Bundle {
    var apsEnvironment: String? {
        return self.entitlements?["aps-environment"] as? String
    }

    var embeddedMobileProvision: [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        // Find first occurrence of bytes for "<plist".
        guard let startRange = data.range(of: Data(bytes: [60, 112, 108, 105, 115, 116])) else {
            return nil
        }
        let possibleEndRange = Range<Data.Index>(uncheckedBounds: (startRange.upperBound, data.endIndex))
        // Find first occurrence of bytes for "</plist>" (after the "<plist" occurrence).
        guard let endRange = data.range(of: Data(bytes: [60, 47, 112, 108, 105, 115, 116, 62]), options: [], in: possibleEndRange) else {
            return nil
        }
        let plistData = data.subdata(in: Range<Data.Index>(uncheckedBounds: (startRange.lowerBound, endRange.upperBound)))
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) else {
            return nil
        }
        return plist as? [String: Any]
    }

    var entitlements: [String: Any]? {
        return self.embeddedMobileProvision?["Entitlements"] as? [String: Any]
    }

    var shortVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "?.?.?"
        }
        return version
    }

    var version: String {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "v\(self.shortVersion) (?)"
        }
        return "v\(self.shortVersion) (\(build))"
    }
}

extension CALayer {
    @discardableResult
    func loop<T>(_ animationKey: String, keyPath: String, from: T, to: T, duration: CFTimeInterval) -> CABasicAnimation {
        var fromValue, toValue: Any
        if let f = from as? UIColor, let t = to as? UIColor {
            fromValue = f.cgColor
            toValue = t.cgColor
        } else {
            fromValue = from
            toValue = to
        }
        let anim = CABasicAnimation(keyPath: keyPath)
        anim.autoreverses = true
        anim.duration = duration
        anim.isRemovedOnCompletion = false
        anim.repeatCount = .infinity
        anim.fromValue = fromValue
        anim.toValue = toValue
        self.add(anim, forKey: animationKey)
        return anim
    }
}

extension Character {
    var isLetter: Bool {
        return self.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
    }
}

fileprivate let deviceColorSpace = CGColorSpaceCreateDeviceRGB()

extension CGContext {
    static func create(with buffer: CVPixelBuffer, alpha: Bool = false) -> CGContext? {
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        let alphaInfo: CGImageAlphaInfo = alpha ? .premultipliedFirst : .noneSkipFirst
        return CGContext(
            data: address,
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: deviceColorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | alphaInfo.rawValue)
    }

    static func create(size: CGSize, alpha: Bool = false) -> CGContext? {
        let alphaInfo: CGImageAlphaInfo = alpha ? .premultipliedFirst : .noneSkipFirst
        // Bytes per row must be a multiple of 64 for Metal compatibility.
        let bytesPerRow: Int = ((((Int(size.width) << 2) - 1) >> 6) + 1) << 6
        return CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: deviceColorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | alphaInfo.rawValue)
    }
}

extension CGImage {
    static func create(with buffer: CVPixelBuffer) -> CGImage? {
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: address,
            size: CVPixelBufferGetDataSize(buffer),
            releaseData: { (_, _, _) in })
            else { return nil }
        return CGImage(
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: deviceColorSpace,
            bitmapInfo: [CGBitmapInfo.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)],
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }
}

extension CGSize {
    var isLandscape: Bool {
        return self.aspectRatio > 1
    }

    var aspectRatio: Float {
        guard self.height > 0 else {
            return 0
        }
        return Float(self.width / self.height)
    }

    var orientationDescription: String {
        if abs(self.width - self.height) < 1 {
            return "Square"
        } else if self.width > self.height {
            return "Landscape"
        } else {
            return "Portrait"
        }
    }
}

extension Data {
    var hex: String {
        let pointer = (self as NSData).bytes.bindMemory(to: UInt8.self, capacity: self.count)
        var hex = ""
        for i in 0..<self.count {
            hex += String(format: "%02x", pointer[i])
        }
        return hex
    }
}

fileprivate let calendar = Calendar.autoupdatingCurrent
fileprivate let formatter = { () -> DateFormatter in
    let formatter = DateFormatter()
    formatter.locale = Locale.autoupdatingCurrent
    formatter.timeZone = TimeZone.autoupdatingCurrent
    return formatter
}()

extension Date {
    var dateLabel: String {
        if self.year == Date().year {
            return self.formatted("EEEE, MMMM d")
        } else {
            return self.formatted("EEEE, MMMM d yyyy")
        }
    }

    var day: Int {
        return calendar.component(.day, from: self)
    }

    var hour: Int {
        return calendar.component(.hour, from: self)
    }

    var minute: Int {
        return calendar.component(.minute, from: self)
    }

    var month: Int {
        return calendar.component(.month, from: self)
    }

    var second: Int {
        return calendar.component(.second, from: self)
    }

    var year: Int {
        return calendar.component(.year, from: self)
    }

    var daysAgo: Int {
        return calendar.dateComponents([.day], from: self, to: Date()).day!
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var timeLabel: String {
        if calendar.isDateInToday(self) {
            return self.formatted("h:mm a")
        } else if calendar.isDateInYesterday(self) {
            return self.formatted("EEE h:mm a")
        } else if self.daysAgo < 7 {
            return self.formatted("EEE")
        } else {
            return self.formatted("MMM d")
        }
    }

    /// Accessible version of the short date format.
    var timeLabelAccessible: String {
        switch self.daysAgo {
        case 0:
            return String.localizedStringWithFormat(
                NSLocalizedString("at %@", comment: "Time status; value is a time"),
                self.formattedTime)
        case 1...6:
            return self.formatted("EEEE")
        default:
            return self.formatted("MMMM d")
        }
    }

    /// Displays short date format.
    var timeLabelShort: String {
        switch self.daysAgo {
        case 0:
            return self.formattedTime
        case 1...6:
            return self.formatted("EEE")
        default:
            return self.formatted("MMM d")
        }
    }

    /// Get a new Date adjusted for the given timezone. Note that Date does not contain timezone information so this method is NOT idempotent.
    func forTimeZone(_ name: String) -> Date? {
        guard let timeZone = TimeZone(identifier: name) else {
            return nil
        }
        let seconds = timeZone.secondsFromGMT(for: self) - TimeZone.current.secondsFromGMT(for: self)
        return Date(timeInterval: TimeInterval(seconds), since: self)
    }

    fileprivate func formatted(_ format: String) -> String {
        formatter.dateFormat = format
        return formatter.string(from: self)
    }

    /// Returns something along the lines of "7 PM".
    fileprivate func formattedHour() -> String {
        let comp = calendar.dateComponents([.hour, .minute], from: self)
        let hour = min(comp.hour! + (comp.minute! >= 30 ? 1 : 0), 23)
        let ampm = hour < 12 ? calendar.amSymbol : calendar.pmSymbol
        let hour12 = hour % 12
        return "\(hour12 > 0 ? hour12 : 12) \(ampm)"
    }

    var weekDay: String {
        return self.formatted("EEEE")
    }
}

extension FileHandle {
    enum FileHandleError: Error {
        case syncFailed
        case writeFailed
    }

    func synchronizeFileThrows() throws {
        if fsync(self.fileDescriptor) == -1 {
            throw FileHandleError.syncFailed
        }
    }

    func writeThrows(_ data: Data) throws {
        var error: FileHandleError?
        data.enumerateBytes { (bytes, range, stop) in
            let size = Darwin.write(self.fileDescriptor, bytes.baseAddress!, bytes.endIndex)
            if size == -1 {
                error = .writeFailed
            }
        }
        if let error = error {
            throw error
        }
    }
}

extension FileManager {
    var freeDiskSpace: Int64? {
        guard
            let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).last,
            let attribs = try? FileManager.default.attributesOfFileSystem(forPath: path),
            let freeSize = attribs[.systemFreeSize] as? Int64
            else { return nil }
        return freeSize
    }
}

private let base62Alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

extension BinaryInteger {
    var base62: String {
        var result = ""
        var quotient = Int64(self)
        while quotient > 0 {
            let remainder = Int(quotient % 62)
            quotient = quotient / 62
            result.insert(base62Alphabet[base62Alphabet.index(base62Alphabet.startIndex, offsetBy: remainder)], at: result.startIndex)
        }
        return result
    }
}

extension Int {
    var countLabelShort: String {
        if self >= 1000000 {
            return "\(String(format: "%.01f", Float(self) / 1000000.0))m"
        } else if self >= 100000 {
            return "\(String(format: "%.0f", Float(self) / 1000.0))k"
        } else if self >= 1000 {
            return "\(String(format: "%.01f", Float(self) / 1000.0))k"
        } else {
            return String(self)
        }
    }

    var formattedWithSeparator: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.locale = Locale.current
        return numberFormatter.string(from: self as NSNumber) ?? "0"
    }
}

extension MessageComposeResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        case .sent:
            return "Sent"
        }
    }
}

extension MutableCollection {
    /// Shuffles the contents of this collection.
    mutating func shuffle() {
        let c = self.count
        guard c > 1 else { return }
        for (firstUnshuffled, unshuffledCount) in zip(self.indices, stride(from: c, to: 1, by: -1)) {
            let i = index(firstUnshuffled, offsetBy: Int(arc4random_uniform(UInt32(unshuffledCount))))
            swapAt(firstUnshuffled, i)
        }
    }
}

extension Sequence {
    /// Returns an array with the contents of this sequence, shuffled.
    func shuffled() -> [Element] {
        var result = Array(self)
        result.shuffle()
        return result
    }
}

extension Sequence where Iterator.Element == String {
    func localizedJoin() -> String {
        var g = self.makeIterator()
        guard let first = g.next() else {
            return ""
        }
        guard let second = g.next() else {
            return first
        }
        guard var last = g.next() else {
            return String.localizedStringWithFormat(
                NSLocalizedString("LIST_TWO", value: "%@ and %@", comment: "List; only two items"), first, second)
        }
        var middle = second
        while let piece = g.next() {
            middle = String.localizedStringWithFormat(
                NSLocalizedString("LIST_MIDDLE", value: "%@, %@", comment: "List; more than three items, middle items"), middle, last)
            last = piece
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("LIST_END", value: "%@ and %@", comment: "List; more than two items, last items"),
            String.localizedStringWithFormat(
                NSLocalizedString("LIST_START", value: "%@, %@", comment: "List; more than two items, first items"), first, middle),
            last)
    }
}

private let initialsRegex = try! NSRegularExpression(pattern: "\\b[^\\W\\d_]", options: [])

extension String {
    static func randomBase62(of length: Int) -> String {
        let range = 0..<length
        let characters = range.map({ (i: Int) -> Character in
            let value = Int(arc4random_uniform(62))
            let index = base62Alphabet.index(base62Alphabet.startIndex, offsetBy: value)
            return base62Alphabet[index]
        })
        return String(characters)
    }

    var hasLetters: Bool {
        let letters = CharacterSet.letters
        return self.rangeOfCharacter(from: letters) != nil
    }

    var hexColor: UIColor? {
        let hex = self.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt32()
        guard Scanner(string: hex).scanHexInt32(&int) else {
            return nil
        }
        let a, r, g, b: UInt32
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    func highlightingMatches(of keyphrase: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: self)
        do {
            let regex = try NSRegularExpression(pattern: keyphrase, options: .caseInsensitive)
            let range = NSRange(location: 0, length: self.utf16.count)
            for match in regex.matches(in: self, options: .withTransparentBounds, range: range) {
                attributedString.addAttribute(NSAttributedStringKey.backgroundColor, value: UIColor.yellow.withAlphaComponent(0.2), range: match.range)
            }
        } catch _ {
            NSLog("Error creating regular expression")
        }
        return attributedString
    }

    func matches(of regex: String) -> [(text: String, groups: [String?])] {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let nsString = self as NSString
            let matches = regex.matches(in: self, range: NSRange(location: 0, length: nsString.length))
            return matches.map { match in
                let full = nsString.substring(with: match.range)
                let groups: [String?] = (0..<match.numberOfRanges).map {
                    let range = match.range(at: $0)
                    return range.location == NSNotFound ? nil : nsString.substring(with: range)
                }
                return (full, groups)
            }
        } catch {
            return []
        }
    }
    
    func searchURL() -> URL? {
        let text = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        var maybeURL: URL?
        if text.contains("."), var c = URLComponents(string: text) {
            if c.scheme != "http" && c.scheme != "https" {
                c.scheme = "http"
            }
            maybeURL = c.url
        } else {
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "safe", value: "active"), URLQueryItem(name: "tbm", value: "vid")]
            maybeURL = c.url
        }
        return maybeURL
    }

    var intValue: Int? {
        return NumberFormatter().number(from: self)?.intValue
    }
}

extension UIAlertController {
    func addCancel(title: String = "Cancel", handler: (() -> ())? = nil) {
        self.addAction(UIAlertAction(title: title, style: .cancel, handler: { _ in handler?() }))
    }
}

extension UIButton {
    func af_setImageBiased(
        for state: UIControlState,
        url: URL,
        placeholderImage: UIImage? = nil,
        progress: ImageDownloader.ProgressHandler? = nil,
        progressQueue: DispatchQueue = DispatchQueue.main,
        completion: ((DataResponse<UIImage>) -> Void)? = nil)
    {
        let filter: ImageFilter?
        if let view = self.imageView {
            filter = AspectScaledToFillSizeBiasedFilter(view: view, biasX: 0.5, y: 0.25)
        } else {
            filter = nil
        }
        self.af_setImage(
            for: state,
            url: url,
            placeholderImage: placeholderImage,
            filter: filter,
            progress: progress,
            progressQueue: progressQueue,
            completion: completion
        )
    }

    func setImageWithAnimation(_ image: UIImage?) {
        guard let imageView = self.imageView else {
            return
        }
        if let newImage = image, let oldImage = imageView.image {
            let crossFade = CABasicAnimation(keyPath: "contents")
            crossFade.duration = 0.1
            crossFade.fromValue = oldImage.cgImage
            crossFade.toValue = newImage.cgImage
            crossFade.isRemovedOnCompletion = true
            crossFade.fillMode = kCAFillModeForwards
            self.imageView?.layer.add(crossFade, forKey: "animateContents")
        }
        self.setImage(image, for: .normal)
    }

    func setTitleWithoutAnimation(_ title: String) {
        UIView.performWithoutAnimation {
            self.setTitle(title, for: .normal)
            self.layoutIfNeeded()
        }
    }
}

extension UIColor {
    static var uiRed: UIColor {
        return "FF3A3A".hexColor!
    }

    static var uiBlue: UIColor {
        return "4C90F5".hexColor!
    }

    static var uiPink: UIColor {
        return "FC1031".hexColor!
    }

    static var uiDarkPurple: UIColor {
        return "3E2666".hexColor!
    }

    static var uiPurple: UIColor {
        return "56358C".hexColor!
    }
    
    static var uiYellow: UIColor {
        return "FFE205".hexColor!
    }

    static var uiDarkGray: UIColor {
        return "313131".hexColor!
    }

    static var uiBlack: UIColor {
        return "101010".hexColor!
    }
}

extension UIDevice {
    enum Processor: Int, Comparable {
        case arbitrary = -1
        // Samsung ARMs
        case apl0098
        case apl0278
        case apl0298
        case apl2298
        // A4
        case apl0398
        // A5
        case apl0498
        case apl2498
        case apl7498
        // A5X
        case apl5498
        // A6
        case apl0598
        // A6X
        case apl5598
        // A7
        case apl0698
        case apl5698
        // A8
        case apl1011
        // A8X
        case apl1012
        // A9
        case apl0898
        case apl1022
        // A9X
        case apl1021
        // A10 Fusion
        case apl1w24
        // A11
        case apl1w72
        // ???
        case future = 99999

        static func <(lhs: Processor, rhs: Processor) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8 , value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    var modelName: String {
        let identifier = self.modelIdentifier
        switch identifier {
        case "iPod5,1":                                  return "iPod Touch 5"
        case "iPod7,1":                                  return "iPod Touch 6"
        case "iPhone3,1", "iPhone3,2", "iPhone3,3":      return "iPhone 4"
        case "iPhone4,1":                                return "iPhone 4s"
        case "iPhone5,1", "iPhone5,2":                   return "iPhone 5"
        case "iPhone5,3", "iPhone5,4":                   return "iPhone 5c"
        case "iPhone6,1", "iPhone6,2":                   return "iPhone 5s"
        case "iPhone7,2":                                return "iPhone 6"
        case "iPhone7,1":                                return "iPhone 6 Plus"
        case "iPhone8,1":                                return "iPhone 6s"
        case "iPhone8,2":                                return "iPhone 6s Plus"
        case "iPhone8,4":                                return "iPhone SE"
        case "iPhone9,1", "iPhone9,3":                   return "iPhone 7"
        case "iPhone9,2", "iPhone9,4":                   return "iPhone 7 Plus"
        case "iPhone10,1", "iPhone10,4":                 return "iPhone 8"
        case "iPhone10,2", "iPhone10,5":                 return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6":                 return "iPhone X"
        case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4": return "iPad 2"
        case "iPad3,1", "iPad3,2", "iPad3,3":            return "iPad 3"
        case "iPad3,4", "iPad3,5", "iPad3,6":            return "iPad 4"
        case "iPad4,1", "iPad4,2", "iPad4,3":            return "iPad Air"
        case "iPad5,3", "iPad5,4":                       return "iPad Air 2"
        case "iPad2,5", "iPad2,6", "iPad2,7":            return "iPad Mini"
        case "iPad4,4", "iPad4,5", "iPad4,6":            return "iPad Mini 2"
        case "iPad4,7", "iPad4,8", "iPad4,9":            return "iPad Mini 3"
        case "iPad5,1", "iPad5,2":                       return "iPad Mini 4"
        case "iPad6,7", "iPad6,8":                       return "iPad Pro"
        case "AppleTV5,3":                               return "Apple TV"
        case "i386", "x86_64":                           return "Simulator"
        default:                                         return identifier
        }
    }

    var processor: Processor {
        let identifier = self.modelIdentifier
        switch identifier {
        case "iPod5,1":                                  return .apl2498
        case "iPod7,1":                                  return .apl1011
        case "iPhone3,1", "iPhone3,2", "iPhone3,3":      return .apl0398
        case "iPhone4,1":                                return .apl0498
        case "iPhone5,1", "iPhone5,2":                   return .apl0598
        case "iPhone5,3", "iPhone5,4":                   return .apl0598
        case "iPhone6,1", "iPhone6,2":                   return .apl0698
        case "iPhone7,2":                                return .apl1011
        case "iPhone7,1":                                return .apl1011
        case "iPhone8,1":                                return .apl0898 // or .apl1022?
        case "iPhone8,2":                                return .apl0898 // or .apl1022?
        case "iPhone8,4":                                return .apl0898 // or .apl1022?
        case "iPhone9,1", "iPhone9,3":                   return .apl1w24
        case "iPhone9,2", "iPhone9,4":                   return .apl1w24
        case "iPhone10,1", "iPhone10,4":                 return .apl1w72
        case "iPhone10,2", "iPhone10,5":                 return .apl1w72
        case "iPhone10,3", "iPhone10,6":                 return .apl1w72
        case "iPad2,1", "iPad2,2", "iPad2,3":            return .apl0498
        case "iPad2,4":                                  return .apl2498
        case "iPad3,1", "iPad3,2", "iPad3,3":            return .apl5498
        case "iPad3,4", "iPad3,5", "iPad3,6":            return .apl5598
        case "iPad4,1", "iPad4,2", "iPad4,3":            return .apl5698
        case "iPad5,3", "iPad5,4":                       return .apl1012
        case "iPad2,5", "iPad2,6", "iPad2,7":            return .apl2498
        case "iPad4,4", "iPad4,5", "iPad4,6":            return .apl0698
        case "iPad4,7", "iPad4,8", "iPad4,9":            return .apl0698
        case "iPad5,1", "iPad5,2":                       return .apl1011
        case "iPad6,7", "iPad6,8":                       return .apl1021
        case "AppleTV5,3":                               return .apl1011
        default:                                         return .future
        }
    }
}

extension UIFont {
    class func annotationFont(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "VarelaRound-Regular", size: size)!
    }

    class func fredokaOneFont(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "FredokaOne-Regular", size: size)!
    }

    class func materialFont(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "MaterialIcons-Regular", size: size)!
    }

    class func monospacedDigitsFont(ofSize size: CGFloat) -> UIFont {
        let feature = [
            UIFontDescriptor.FeatureKey.featureIdentifier: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.typeIdentifier: kMonospacedNumbersSelector,
            ]
        let baseDescriptor = UIFont.systemFont(ofSize: size).fontDescriptor
        let attributes = [UIFontDescriptor.AttributeName.featureSettings: [feature]]
        return UIFont(descriptor: baseDescriptor.addingAttributes(attributes), size: size)
    }
}

extension UIImage {
    func save(temporary: Bool = true) -> URL? {
        guard let directory = temporary ? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true) :
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
            let data = UIImageJPEGRepresentation(self, 0.7) else {
                return nil
        }
        let randomId = ProcessInfo.processInfo.globallyUniqueString
        let url = directory.appendingPathComponent(randomId).appendingPathExtension("jpg")
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("WARNING: Could not save image")
            return nil
        }
    }
}

extension UIImageView {
    func af_setImageBiased(
        withURL url: URL,
        placeholderImage: UIImage? = nil,
        progress: ImageDownloader.ProgressHandler? = nil,
        progressQueue: DispatchQueue = DispatchQueue.main,
        imageTransition: ImageTransition = .noTransition,
        runImageTransitionIfCached: Bool = false,
        completion: ((DataResponse<UIImage>) -> Void)? = nil)
    {
        let filter = AspectScaledToFillSizeBiasedFilter(view: self, biasX: 0.5, y: 0.25)
        self.af_setImage(
            withURL: url,
            placeholderImage: placeholderImage,
            filter: filter,
            progress: progress,
            progressQueue: progressQueue,
            imageTransition: imageTransition,
            runImageTransitionIfCached: runImageTransitionIfCached,
            completion: completion
        )
    }
}

extension UINavigationController {
    var secondFromTopViewController: UIViewController? {
        let count = self.viewControllers.count
        guard count >= 2 else {
            return nil
        }
        return self.viewControllers[count - 2]
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        self.interactivePopGestureRecognizer?.delegate = nil
    }

    func pushViewControllerModal(_ controller: UIViewController) {
        self.setModalTransition(isPop: false)
        self.pushViewController(controller, animated: false)
    }

    func popViewControllerModal() {
        self.presentedViewController?.dismiss(animated: true)
        self.setModalTransition()
        self.popViewController(animated: false)
    }

    func popToRootViewControllerModal() {
        self.presentedViewController?.dismiss(animated: true)
        self.setModalTransition()
        self.popToRootViewController(animated: false)
    }

    func popToViewControllerModal(_ viewController: UIViewController) {
        self.presentedViewController?.dismiss(animated: true)
        self.setModalTransition()
        self.popToViewController(viewController, animated: false)
    }

    private func setModalTransition(isPop: Bool = true) {
        let transition = CATransition()
        transition.duration = 0.4
        transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionDefault)
        transition.type = kCATransitionReveal
        transition.subtype = kCATransitionFromBottom
        if isPop {
            transition.type = kCATransitionReveal
            transition.subtype = kCATransitionFromBottom
        } else {
            transition.type = kCATransitionMoveIn
            transition.subtype = kCATransitionFromTop
        }
        self.view.layer.add(transition, forKey: kCATransition)
    }
}

extension UITableView {
    func scrollToTop() {
        let insetY: CGFloat
        if #available(iOS 11.0, *) {
            insetY = self.contentInset.top + self.safeAreaInsets.top
        } else {
            insetY = self.contentInset.top
        }
        self.setContentOffset(CGPoint(x: 0, y: -insetY), animated: true)
    }
}

extension UITextField {
    func setPlaceholder(text: String, color: UIColor) {
        self.attributedPlaceholder = NSAttributedString(string: text, attributes: [NSAttributedStringKey.foregroundColor: color])
    }
}

extension UIView {
    var layoutDirection: UIUserInterfaceLayoutDirection {
        return UIView.userInterfaceLayoutDirection(for: self.semanticContentAttribute)
    }

    var screenEstate: CGFloat {
        guard let window = self.window else {
            return 0
        }
        let frame = CGRect(origin: self.convert(self.frame.origin, to: nil),
                           size: self.frame.size)
        let intersection = window.frame.intersection(frame)
        return intersection.width * intersection.height
    }

    @IBInspectable var borderColor: UIColor? {
        get { return UIColor(cgColor: self.layer.borderColor!) }
        set { self.layer.borderColor = newValue?.cgColor }
    }

    @IBInspectable var shadowColor: UIColor? {
        get { return UIColor(cgColor: self.layer.shadowColor!) }
        set { self.layer.shadowColor = newValue?.cgColor }
    }

    func hideAnimated(callback: (() -> ())? = nil) {
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState],
            animations: { self.alpha = 0 },
            completion: { success in
                if success {
                    self.isHidden = true
                    self.alpha = 1
                }
                callback?()
        })
    }

    func blink() {
        self.alpha = 0
        self.isHidden = false
        UIView.animate(
            withDuration: 0.7,
            delay: 0,
            options: [.autoreverse, .repeat, .curveEaseOut, .allowUserInteraction],
            animations: { self.alpha = 1 })
    }

    /// A quick size pulse animation for UI feedback
    func pulse(_ scale: Double = 1.3) {
        let s = CGFloat(scale)
        UIView.animate(withDuration: 0.1, delay: 0.0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.transform = CGAffineTransform(scaleX: s, y: s)
            }, completion: { success in
                UIView.animate(withDuration: 0.1, delay: 0.0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                    self.transform = CGAffineTransform.identity
                    })
        })
    }

    func set(shadowX x: CGFloat, y: CGFloat, radius: CGFloat, color: UIColor, opacity: Float) {
        self.layer.shadowColor = color.cgColor
        self.layer.shadowOffset = CGSize(width: x, height: y)
        self.layer.shadowOpacity = opacity
        self.layer.shadowRadius = radius
    }

    func setHeavyShadow() {
        self.set(shadowX: 0, y: 1, radius: 3, color: .black, opacity: 1)
    }

    func setSoftShadow() {
        self.set(shadowX: 0, y: 1, radius: 1.5, color: .black, opacity: 0.7)
    }

    func setTinyShadow() {
        self.set(shadowX: 0, y: 0.5, radius: 1, color: .black, opacity: 1)
    }

    func showAnimated() {
        if self.isHidden {
            self.alpha = 0
        }
        self.isHidden = false
        UIView.animate(withDuration: 0.15, delay: 0, options: .beginFromCurrentState, animations: {
            self.alpha = 1
        })
    }

    func unsetShadow() {
        self.layer.shadowColor = nil
        self.layer.shadowOffset = .zero
        self.layer.shadowOpacity = 0
        self.layer.shadowRadius = 0
    }
}

extension UIViewController {
    func configurePopover(sourceView: UIView, sourceRect: CGRect? = nil) {
        if self is UIVideoEditorController && UIDevice.current.userInterfaceIdiom == .pad {
            self.modalPresentationStyle = .popover
        }
        guard let popover = self.popoverPresentationController else {
            return
        }
        popover.sourceView = sourceView
        popover.sourceRect = sourceRect ?? sourceView.bounds
    }
}

extension URL {
    /// Returns the file size of the URL in bytes, or nil if getting the file size failed. Only works for file URLs.
    var fileSize: Int64? {
        guard self.isFileURL else {
            return nil
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: self.path)
            return attributes[.size] as? Int64
        } catch let e {
            Logging.debug("File Attributes Error", ["Error": e.localizedDescription])
            return nil
        }
    }

    /// Parses a query string and returns a dictionary that contains all the key/value pairs.
    func parseQueryString() -> [String: [String]] {
        guard let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var data = [String: [String]]()
        for item in items {
            var list = data[item.name] ?? [String]()
            if let value = item.value {
                list.append(value)
            }
            data[item.name] = list
        }
        return data
    }

    /// Creates a random file path to a file in the temporary directory.
    static func temporaryFileURL(_ fileExtension: String) -> URL {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let randomId = ProcessInfo.processInfo.globallyUniqueString
        return temp.appendingPathComponent(randomId).appendingPathExtension(fileExtension)
    }
}
